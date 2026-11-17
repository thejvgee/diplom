import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart'
    show DocumentReference, FirebaseFirestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/holding.dart';
import '../models/transaction.dart';

/// Симуляцийн хөрөнгө оруулалтын данс.
///
/// * Хэрэглэгч бүрийн багц тусдаа: Firestore-ийн `users/{uid}/portfolio/state`
///   баримтад хадгалагдаж, утсанд кэшлэгдэнэ (интернэтгүй үед ч ажиллана).
/// * Хувьцаа, гүйлгээ, бэлэн мөнгө, өдөр тутмын үнэлгээний түүх бүгд
///   хадгалагдана — апп дахин нээхэд алдагдахгүй.
class PortfolioProvider extends ChangeNotifier {
  /// Шинэ хэрэглэгчид олгох симуляцийн эхний мөнгө.
  static const double initialCash = 10000000;
  static const int _maxHistoryPoints = 730;

  final PortfolioRemoteStore? _remote;
  final Future<SharedPreferences> Function() _prefs;
  StreamSubscription<String?>? _authSub;

  List<Holding> _holdings = [];
  List<Transaction> _transactions = [];
  double _cashBalance = initialCash;
  List<ValuePoint> _valueHistory = [];
  Map<String, double> _previousCloses = {};
  int _updatedAt = 0;

  String? _uid;
  int _loadToken = 0;
  bool _isLoading = true;
  String _error = '';
  DateTime? _lastHistorySave;
  bool _disposed = false;

  PortfolioProvider({
    PortfolioRemoteStore? remote,
    Stream<String?>? userIds,
    Future<SharedPreferences> Function()? prefs,
  })  : _remote = remote ?? (userIds == null ? FirestorePortfolioStore() : null),
        _prefs = prefs ?? SharedPreferences.getInstance {
    final ids = userIds ??
        FirebaseAuth.instance.authStateChanges().map((u) => u?.uid);
    _authSub = ids.listen(_switchUser);
  }

  // Getters
  List<Holding> get holdings => List.unmodifiable(_holdings);
  List<Transaction> get transactions => List.unmodifiable(_transactions);
  double get cashBalance => _cashBalance;
  List<ValuePoint> get valueHistory => List.unmodifiable(_valueHistory);
  bool get isLoading => _isLoading;
  String get error => _error;
  bool get hasError => _error.isNotEmpty;
  String? get userId => _uid;

  double get holdingsValue => _holdings.fold<double>(
      0, (sum, h) => sum + h.quantity * (h.currentPrice > 0 ? h.currentPrice : h.averageCost));

  double get totalValue => _cashBalance + holdingsValue;

  // ---------------------------------------------------------------------------
  // Ачаалах / хадгалах
  // ---------------------------------------------------------------------------

  Future<void> _switchUser(String? uid) async {
    final token = ++_loadToken;
    _uid = uid;
    _resetState();
    _isLoading = true;
    _notify();

    try {
      final local = await _loadLocal(uid);
      if (token != _loadToken) return;
      if (local != null) _apply(local);
      _isLoading = local == null && uid != null && _remote != null;
      _notify();

      if (uid != null && _remote != null) {
        Map<String, dynamic>? remote;
        try {
          remote = await _remote.load(uid);
        } catch (e) {
          debugPrint('Portfolio remote load failed: $e');
        }
        if (token != _loadToken) return;
        final remoteAt = (remote?['updatedAt'] as num?)?.toInt() ?? -1;
        if (remote != null && remoteAt >= _updatedAt) {
          _apply(remote);
          await _saveLocal();
        } else if (local != null) {
          // Утсан дээрх хувилбар шинэ (жишээ нь офлайн гүйлгээ) → серверт илгээнэ
          unawaited(_saveRemote());
        } else {
          await _save(); // Шинэ хэрэглэгч: эхний дансыг үүсгэнэ
        }
      } else if (local == null) {
        await _save();
      }
      _error = '';
    } catch (e) {
      _error = 'Багцын мэдээлэл ачаалахад алдаа гарлаа: $e';
    } finally {
      if (token == _loadToken) {
        _isLoading = false;
        _notify();
      }
    }
  }

  void _resetState() {
    _holdings = [];
    _transactions = [];
    _cashBalance = initialCash;
    _valueHistory = [];
    _updatedAt = 0;
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'cashBalance': _cashBalance,
        'holdings': [for (final h in _holdings) h.toJson()],
        'transactions': [for (final t in _transactions) t.toJson()],
        'valueHistory': [for (final p in _valueHistory) p.toJson()],
        'updatedAt': _updatedAt,
      };

  void _apply(Map<String, dynamic> json) {
    _cashBalance = (json['cashBalance'] as num?)?.toDouble() ?? initialCash;
    _holdings = [
      for (final h in json['holdings'] as List? ?? [])
        Holding.fromJson(Map<String, dynamic>.from(h as Map))
    ];
    _transactions = [
      for (final t in json['transactions'] as List? ?? [])
        Transaction.fromJson(Map<String, dynamic>.from(t as Map))
    ];
    _valueHistory = [
      for (final p in json['valueHistory'] as List? ?? [])
        ValuePoint.fromJson(Map<String, dynamic>.from(p as Map))
    ];
    _updatedAt = (json['updatedAt'] as num?)?.toInt() ?? 0;
  }

  String _localKey(String? uid) => 'portfolio_v2_${uid ?? 'guest'}';

  Future<Map<String, dynamic>?> _loadLocal(String? uid) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_localKey(uid));
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _saveLocal() async {
    final prefs = await _prefs();
    await prefs.setString(_localKey(_uid), jsonEncode(toJson()));
  }

  Future<void> _saveRemote() async {
    final uid = _uid;
    if (uid == null || _remote == null) return;
    try {
      await _remote.save(uid, toJson());
    } catch (e) {
      // Офлайн үед Firestore өөрөө дараалалд хийдэг; бусад алдааг л бүртгэнэ.
      debugPrint('Portfolio remote save failed: $e');
    }
  }

  Future<void> _save() async {
    _updatedAt = DateTime.now().millisecondsSinceEpoch;
    _recordSnapshot();
    await _saveLocal();
    unawaited(_saveRemote());
  }

  // ---------------------------------------------------------------------------
  // Гүйлгээ
  // ---------------------------------------------------------------------------

  Future<bool> buyStock(String symbol, double quantity, double price) async {
    if (quantity <= 0 || price <= 0 || _isLoading) return false;
    final totalCost = quantity * price;
    if (totalCost > _cashBalance + 1e-6) return false;

    _cashBalance -= totalCost;
    final i = _holdings.indexWhere((h) => h.symbol == symbol);
    if (i >= 0) {
      final h = _holdings[i];
      final newQty = h.quantity + quantity;
      _holdings[i] = h.copyWith(
        quantity: newQty,
        averageCost: (h.totalCost + totalCost) / newQty,
        currentPrice: price,
      );
    } else {
      _holdings.add(Holding(
        symbol: symbol,
        quantity: quantity,
        averageCost: price,
        currentPrice: price,
      ));
    }
    _transactions.add(Transaction(
      symbol: symbol,
      action: 'buy',
      quantity: quantity,
      price: price,
      totalAmount: totalCost,
      timestamp: DateTime.now(),
    ));
    return _commit();
  }

  Future<bool> sellStock(String symbol, double quantity, double price) async {
    if (quantity <= 0 || price <= 0 || _isLoading) return false;
    final i = _holdings.indexWhere((h) => h.symbol == symbol);
    if (i < 0 || _holdings[i].quantity < quantity - 1e-9) return false;

    final amount = quantity * price;
    _cashBalance += amount;
    final remaining = _holdings[i].quantity - quantity;
    if (remaining > 1e-9) {
      _holdings[i] = _holdings[i].copyWith(quantity: remaining, currentPrice: price);
    } else {
      _holdings.removeAt(i);
    }
    _transactions.add(Transaction(
      symbol: symbol,
      action: 'sell',
      quantity: quantity,
      price: price,
      totalAmount: amount,
      timestamp: DateTime.now(),
    ));
    return _commit();
  }

  Future<void> addCash(double amount) async {
    if (amount <= 0 || _isLoading) return;
    _cashBalance += amount;
    _transactions.add(Transaction(
      symbol: 'CASH',
      action: 'deposit',
      quantity: 1,
      price: amount,
      totalAmount: amount,
      timestamp: DateTime.now(),
    ));
    await _commit();
  }

  Future<bool> _commit() async {
    try {
      await _save();
      _notify();
      return true;
    } catch (e) {
      _error = 'Хадгалахад алдаа гарлаа: $e';
      _notify();
      return false;
    }
  }

  /// Дансыг анхны төлөвт оруулна (симуляцийг шинээр эхлүүлэх).
  Future<void> resetPortfolio() async {
    _resetState();
    await _commit();
  }

  /// Хэрэглэгчийн бүх багцын өгөгдлийг устгана (бүртгэл устгах үед).
  Future<void> deleteAllData() async {
    final uid = _uid;
    if (uid != null && _remote != null) await _remote.delete(uid);
    final prefs = await _prefs();
    await prefs.remove(_localKey(uid));
    _resetState();
    _notify();
  }

  List<Transaction> getTransactionsForSymbol(String symbol) =>
      _transactions.where((t) => t.symbol == symbol).toList();

  List<Transaction> getRecentTransactions({int days = 30}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _transactions.where((t) => t.timestamp.isAfter(cutoff)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<double> getTotalPortfolioValue() async => totalValue;

  // ---------------------------------------------------------------------------
  // Бодит ханш ба гүйцэтгэл
  // ---------------------------------------------------------------------------

  /// Бодит ханшаар (MSE, крипто) хувьцаануудын одоогийн үнийг шинэчилнэ.
  /// [previousCloses] өгвөл өнөөдрийн өөрчлөлтийг тооцно.
  void updateLivePrices(Map<String, double> prices,
      {Map<String, double>? previousCloses}) {
    if (previousCloses != null) {
      _previousCloses = {..._previousCloses, ...previousCloses};
    }
    var changed = false;
    _holdings = _holdings.map((h) {
      final price = prices[h.symbol];
      if (price == null || price <= 0 || price == h.currentPrice) return h;
      changed = true;
      return h.copyWith(currentPrice: price);
    }).toList();
    if (!changed || _isLoading) return;

    _recordSnapshot();
    // Үнэлгээний түүхийг 15 минут тутамд л хадгална (Firestore-ийн бичилт хэмнэх)
    final now = DateTime.now();
    if (_lastHistorySave == null ||
        now.difference(_lastHistorySave!) > const Duration(minutes: 15)) {
      _lastHistorySave = now;
      unawaited(_save());
    }
    _notify();
  }

  /// Өнөөдрийн өөрчлөлт (₮): Σ ширхэг × (одоогийн ханш − өмнөх өдрийн хаалт).
  /// Ханш мэдэгдэхгүй бол null.
  double? get dayChange {
    var sum = 0.0;
    var known = false;
    for (final h in _holdings) {
      final prev = _previousCloses[h.symbol];
      if (prev == null || prev <= 0 || h.currentPrice <= 0) continue;
      sum += h.quantity * (h.currentPrice - prev);
      known = true;
    }
    return known ? sum : null;
  }

  /// [days] хоногийн өмнөх үнэлгээнээс хэр өөрчлөгдсөн (₮). Түүх хүрэлцэхгүй бол null.
  double? changeSince(int days) {
    final cutoff = _day(DateTime.now()).subtract(Duration(days: days));
    ValuePoint? base;
    for (final p in _valueHistory) {
      if (!p.day.isAfter(cutoff)) base = p;
    }
    if (base == null) return null;
    return totalValue - base.value;
  }

  /// Өдөр бүрийн сүүлийн үнэлгээг хадгална (графикт).
  void _recordSnapshot() {
    final today = _day(DateTime.now());
    final value = totalValue;
    if (_valueHistory.isNotEmpty && _valueHistory.last.day == today) {
      _valueHistory[_valueHistory.length - 1] = ValuePoint(today, value);
    } else {
      _valueHistory.add(ValuePoint(today, value));
      if (_valueHistory.length > _maxHistoryPoints) {
        _valueHistory.removeRange(0, _valueHistory.length - _maxHistoryPoints);
      }
    }
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    super.dispose();
  }
}

/// Нэг өдрийн багцын нийт үнэлгээ.
class ValuePoint {
  final DateTime day;
  final double value;
  const ValuePoint(this.day, this.value);

  Map<String, dynamic> toJson() =>
      {'day': day.toIso8601String().substring(0, 10), 'value': value};

  factory ValuePoint.fromJson(Map<String, dynamic> j) =>
      ValuePoint(DateTime.parse(j['day'] as String), (j['value'] as num).toDouble());
}

/// Багцыг серверт хадгалах интерфэйс (тестэд хуурамчаар солих боломжтой).
abstract class PortfolioRemoteStore {
  Future<Map<String, dynamic>?> load(String uid);
  Future<void> save(String uid, Map<String, dynamic> data);
  Future<void> delete(String uid);
}

class FirestorePortfolioStore implements PortfolioRemoteStore {
  DocumentReference<Map<String, dynamic>> _doc(String uid) => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('portfolio')
      .doc('state');

  @override
  Future<Map<String, dynamic>?> load(String uid) async {
    final snap = await _doc(uid).get().timeout(const Duration(seconds: 10));
    return snap.data();
  }

  @override
  Future<void> save(String uid, Map<String, dynamic> data) =>
      _doc(uid).set(data);

  @override
  Future<void> delete(String uid) => _doc(uid).delete();
}

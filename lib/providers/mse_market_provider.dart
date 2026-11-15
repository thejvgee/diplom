import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/mse_quote.dart';
import '../services/mse_service.dart';

/// MSE-ийн ханшийг үе үе татаж, дэлгэцүүдэд түгээдэг provider.
///
/// * Арилжааны цагаар (Даваа–Баасан ~10:00–13:00 УБ) [openInterval] тутам,
///   бусад үед [closedInterval] тутам шинэчилнэ.
/// * Зөвхөн сонгосон ангиллын болон багцад байгаа хувьцааны ханшийг татна.
class MseMarketProvider extends ChangeNotifier {
  final MseService _service;
  final Duration openInterval;
  final Duration closedInterval;

  /// Нэг дор хэдэн хүсэлт явуулах вэ (сайтад ачаалал бага өгөх).
  static const int _concurrency = 4;

  MseMarketProvider({
    MseService? service,
    this.openInterval = const Duration(seconds: 60),
    this.closedInterval = const Duration(minutes: 15),
  }) : _service = service ?? MseService();

  List<MseSecurity> _securities = [];
  final Map<String, MseQuote> _quotes = {};
  final Map<String, List<MseDailyBar>> _history = {};
  final Set<String> _extraSymbols = {};
  int _category = 1;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _pendingRefresh = false;
  String? _error;
  DateTime? _lastUpdated;
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;

  List<MseSecurity> get securities => _securities;
  List<MseSecurity> get visibleSecurities =>
      _securities.where((s) => s.category == _category).toList();
  Map<String, MseQuote> get quotes => Map.unmodifiable(_quotes);
  int get category => _category;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  bool get isMarketOpen => MseService.isMarketOpen();

  MseQuote? quoteFor(String symbol) => _quotes[symbol];
  MseSecurity? securityFor(String symbol) {
    for (final s in _securities) {
      if (s.symbol == symbol) return s;
    }
    return null;
  }

  /// Сүүлийн ханшуудыг {symbol: price} хэлбэрээр (багцын үнэлгээнд).
  Map<String, double> get lastPrices => {
    for (final q in _quotes.values) q.symbol: q.price,
  };

  /// Эхлүүлэх. Олон удаа дуудахад зөвхөн нэг удаа ажиллана.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refresh(reloadList: true);
    _scheduleNext();
  }

  /// Багцад байгаа хувьцааг ангиллаас үл хамааран үргэлж шинэчилж байх.
  void trackSymbols(Iterable<String> symbols) {
    final before = _extraSymbols.length;
    _extraSymbols.addAll(symbols);
    if (_extraSymbols.length != before && _securities.isNotEmpty) {
      unawaited(refresh());
    }
  }

  Future<void> setCategory(int category) async {
    if (category == _category) return;
    _category = category;
    _notify();
    await refresh();
  }

  Future<void> refresh({bool reloadList = false}) async {
    if (_isRefreshing) {
      // Ангилал солигдсон гэх мэт үед дараагийн шинэчлэлийг хойшлуулна.
      _pendingRefresh = true;
      return;
    }
    _isRefreshing = true;
    if (_securities.isEmpty) _isLoading = true;
    _notify();

    try {
      if (reloadList || _securities.isEmpty) {
        _securities = await _service.fetchSecurities();
      }

      final targets = <MseSecurity>[
        ...visibleSecurities,
        ..._securities.where(
          (s) => s.category != _category && _extraSymbols.contains(s.symbol),
        ),
      ];

      final failures = <String>[];
      for (var i = 0; i < targets.length; i += _concurrency) {
        final batch = targets.skip(i).take(_concurrency);
        await Future.wait(
          batch.map((sec) async {
            try {
              _quotes[sec.symbol] = await _service.fetchQuote(sec);
            } catch (e) {
              failures.add(sec.symbol);
              debugPrint('MSE quote error ${sec.symbol}: $e');
            }
          }),
        );
        if (_disposed) return;
        _notify(); // Ирсэн ханшийг шууд харуулна.
      }

      _lastUpdated = DateTime.now();
      _error =
          failures.length == targets.length && targets.isNotEmpty
              ? 'MSE-ээс ханш татаж чадсангүй. Интернэт холболтоо шалгана уу.'
              : null;
    } catch (e) {
      _error = 'MSE-ийн мэдээлэл татахад алдаа гарлаа: $e';
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      _notify();
      if (_pendingRefresh && !_disposed) {
        _pendingRefresh = false;
        unawaited(refresh());
      }
    }
  }

  /// Дэлгэрэнгүй графикт зориулсан түүх (кэштэй).
  Future<List<MseDailyBar>> historyFor(String symbol) async {
    final cached = _history[symbol];
    if (cached != null) return cached;
    final sec = securityFor(symbol);
    if (sec == null) return [];
    final bars = await _service.fetchHistory(sec);
    _history[symbol] = bars;
    return bars;
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (_disposed) return;
    final interval = isMarketOpen ? openInterval : closedInterval;
    _timer = Timer(interval, () async {
      await refresh();
      _scheduleNext();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

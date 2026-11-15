import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/crypto_service.dart';

/// Крипто ханшийг 30 секунд тутам шинэчилж, төгрөг рүү хөрвүүлнэ.
class CryptoMarketProvider extends ChangeNotifier {
  static const Map<String, String> assets = {
    'BTC': 'Bitcoin',
    'ETH': 'Ethereum',
  };

  final CryptoService _service;
  final Duration interval;
  CryptoMarketProvider({CryptoService? service, this.interval = const Duration(seconds: 30)})
      : _service = service ?? CryptoService();

  final Map<String, CryptoQuote> _quotes = {};
  final Map<String, List<double>> _closes = {};
  final Map<String, DateTime> _closesAt = {};
  double? _usdMnt;
  DateTime? _fxAt;
  DateTime? _lastUpdated;
  String? _error;
  bool _isLoading = false;
  Timer? _timer;
  bool _disposed = false;

  List<CryptoQuote> get quotes => [
        for (final s in assets.keys)
          if (_quotes[s] != null) _quotes[s]!
      ];
  double? get usdMnt => _usdMnt;
  DateTime? get lastUpdated => _lastUpdated;
  String? get error => _error;
  bool get isLoading => _isLoading;

  CryptoQuote? quoteFor(String symbol) => _quotes[symbol];

  /// Төгрөгөөрх үнэ (ханш мэдэгдэхгүй бол 0).
  double priceMnt(String symbol) {
    final q = _quotes[symbol];
    if (q == null || _usdMnt == null) return 0;
    return q.priceUsd * _usdMnt!;
  }

  Map<String, double> get lastPricesMnt => {
        for (final s in _quotes.keys)
          if (priceMnt(s) > 0) s: priceMnt(s)
      };

  List<double>? hourlyCloses(String symbol) => _closes[symbol];

  void start() {
    if (_timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    _notify();
    try {
      // Валютын ханш өдөрт нэг удаа шинэчлэгддэг тул 1 цаг кэшлэнэ
      if (_usdMnt == null ||
          _fxAt == null ||
          DateTime.now().difference(_fxAt!) > const Duration(hours: 1)) {
        _usdMnt = await _service.fetchUsdMnt();
        _fxAt = DateTime.now();
      }
      for (final q in await _service.fetchQuotes(assets)) {
        _quotes[q.symbol] = q;
      }
      for (final s in assets.keys) {
        final at = _closesAt[s];
        if (at == null || DateTime.now().difference(at) > const Duration(minutes: 5)) {
          _closes[s] = await _service.fetchHourlyCloses(s);
          _closesAt[s] = DateTime.now();
        }
      }
      _lastUpdated = DateTime.now();
      _error = null;
    } catch (e) {
      _error = 'Крипто ханш татаж чадсангүй: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      _notify();
    }
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

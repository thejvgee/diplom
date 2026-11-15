import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../ai_engine/advisor_engine.dart';
import '../ai_engine/risk_profile.dart';
import '../ai_engine/signals.dart';
import '../models/holding.dart';

/// Өөрийн AI зөвлөхийг (AdvisorEngine) апп-д холбодог provider.
/// Gemini эсвэл өөр гадны API дууддаггүй — бүх тооцоо утсан дээр.
class AdvisorProvider extends ChangeNotifier {
  static const String signalsAsset = 'assets/ai/signals.json';

  SignalSet? _signals;
  AdvisorReport? _report;
  String? _error;
  bool _loading = false;

  SignalSet? get signals => _signals;
  AdvisorReport? get report => _report;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isReady => _signals != null;

  Future<void> load() async {
    if (_signals != null || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      final raw = await rootBundle.loadString(signalsAsset);
      _signals = SignalSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _error = null;
    } catch (e) {
      _error = 'AI загварын өгөгдөл ачаалж чадсангүй: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  StockSignal? signalFor(String symbol) => _signals?.signalFor(symbol);

  Future<AdvisorReport?> analyze({
    required List<Holding> holdings,
    required double cash,
    required String riskTolerance,
    Map<String, double> livePrices = const {},
  }) async {
    await load();
    final signals = _signals;
    if (signals == null) return null;
    try {
      _report = AdvisorEngine(signals).analyze(
        holdings: [
          for (final h in holdings)
            HoldingInput(
              symbol: h.symbol,
              quantity: h.quantity,
              averageCost: h.averageCost,
              currentPrice: h.currentPrice,
            ),
        ],
        cash: cash,
        profile: RiskProfile.fromKey(riskTolerance),
        livePrices: livePrices,
      );
      _error = null;
    } catch (e) {
      _error = 'Шинжилгээ хийхэд алдаа гарлаа: $e';
    }
    notifyListeners();
    return _report;
  }

  void reset() {
    _report = null;
    notifyListeners();
  }
}

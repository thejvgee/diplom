import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../ai_engine/advisor_engine.dart';
import '../ai_engine/risk_profile.dart';
import '../ai_engine/signals.dart';
import '../models/holding.dart';

/// Дохио хаанаас ирсэн бэ.
enum SignalsSource { bundled, cache, remote }

/// Өөрийн AI зөвлөхийг (AdvisorEngine) апп-д холбодог provider.
/// Gemini эсвэл өөр гадны AI API дууддаггүй — бүх тооцоо утсан дээр.
///
/// Дохио (`signals.json`) гурван эх сурвалжаас ирнэ, хамгийн шинийг нь ашиглана:
/// 1. Апп-д багцалсан хувилбар (`assets/ai/signals.json`) — үргэлж бэлэн.
/// 2. Утсанд кэшлэсэн хувилбар — интернэтгүй үед.
/// 3. Сервер ([remoteUrl]) — GitHub Actions өдөр бүр шинэчилж Firebase
///    Hosting-д нийтэлдэг (.github/workflows/refresh-signals.yml).
class AdvisorProvider extends ChangeNotifier {
  static const String signalsAsset = 'assets/ai/signals.json';
  static const String _cacheKey = 'ai_signals_cache_v1';

  /// `flutter build ... --dart-define=SIGNALS_URL=...`-ээр сольж болно.
  static const String defaultRemoteUrl = String.fromEnvironment(
    'SIGNALS_URL',
    defaultValue: 'https://diplom-23056.web.app/ai/signals.json',
  );

  /// Серверээс хэр олон удаа шалгах вэ.
  static const Duration remoteCheckInterval = Duration(hours: 1);

  /// Сүүлийн арилжааны өдрөөс хойш ийм олон хоног өнгөрвөл "хуучирсан".
  static const int staleAfterDays = 4;

  final String remoteUrl;
  final Future<String> Function(Uri url) _fetch;
  final Future<SharedPreferences> Function() _prefs;

  AdvisorProvider({
    String? remoteUrl,
    Future<String> Function(Uri url)? fetcher,
    Future<SharedPreferences> Function()? prefs,
  })  : remoteUrl = remoteUrl ?? defaultRemoteUrl,
        _fetch = fetcher ?? _httpGet,
        _prefs = prefs ?? SharedPreferences.getInstance;

  SignalSet? _signals;
  SignalsSource? _source;
  AdvisorReport? _report;
  String? _error;
  String? _remoteError;
  bool _loading = false;
  bool _refreshing = false;
  DateTime? _lastRemoteCheck;
  bool _disposed = false;

  SignalSet? get signals => _signals;
  SignalsSource? get source => _source;
  AdvisorReport? get report => _report;
  String? get error => _error;
  String? get remoteError => _remoteError;
  bool get isLoading => _loading;
  bool get isRefreshing => _refreshing;
  bool get isReady => _signals != null;

  /// Хамгийн сүүлийн арилжааны өдөр (дохионы өгөгдлийн огноо).
  DateTime? get dataDate {
    final s = _signals?.signals;
    if (s == null || s.isEmpty) return null;
    return s.map((x) => x.date).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  bool get isStale {
    final d = dataDate;
    if (d == null) return true;
    return DateTime.now().difference(d).inDays > staleAfterDays;
  }

  Future<void> load() async {
    if (_signals != null || _loading) return;
    _loading = true;
    _notify();
    try {
      SignalSet? bundled;
      try {
        bundled = _parse(await rootBundle.loadString(signalsAsset));
      } catch (e) {
        debugPrint('Bundled signals failed: $e');
      }
      SignalSet? cached;
      try {
        final raw = (await _prefs()).getString(_cacheKey);
        if (raw != null) cached = _parse(raw);
      } catch (e) {
        debugPrint('Cached signals failed: $e');
      }

      if (cached != null &&
          (bundled == null || cached.generatedAt.isAfter(bundled.generatedAt))) {
        _signals = cached;
        _source = SignalsSource.cache;
      } else if (bundled != null) {
        _signals = bundled;
        _source = SignalsSource.bundled;
      }
      _error = _signals == null ? 'AI загварын өгөгдөл ачаалж чадсангүй' : null;
    } finally {
      _loading = false;
      _notify();
    }
    unawaited(refreshRemote());
  }

  /// Серверээс хамгийн сүүлийн дохиог татна. Одоогийнхоос шинэ бол
  /// хэрэглэж, утсанд кэшлэнэ. Алдаа гарвал хуучнаараа үлдэнэ.
  Future<void> refreshRemote({bool force = false}) async {
    if (remoteUrl.isEmpty || _refreshing) return;
    final last = _lastRemoteCheck;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < remoteCheckInterval) {
      return;
    }
    _refreshing = true;
    _lastRemoteCheck = DateTime.now();
    _notify();
    try {
      final raw = await _fetch(Uri.parse(remoteUrl));
      final remote = _parse(raw);
      final current = _signals;
      if (current == null || remote.generatedAt.isAfter(current.generatedAt)) {
        _signals = remote;
        _source = SignalsSource.remote;
        _error = null;
        await (await _prefs()).setString(_cacheKey, raw);
      }
      _remoteError = null;
    } catch (e) {
      _remoteError = 'Шинэ дохио татаж чадсангүй: $e';
      debugPrint(_remoteError);
    } finally {
      _refreshing = false;
      _notify();
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
    await refreshRemote(); // цагт нэг л удаа серверт хандана
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
    _notify();
    return _report;
  }

  void reset() {
    _report = null;
    _notify();
  }

  /// Эвдэрсэн эсвэл хоосон файлыг хүлээж авахгүй.
  static SignalSet _parse(String raw) {
    final set = SignalSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (set.signals.isEmpty) throw const FormatException('Дохио хоосон');
    return set;
  }

  static Future<String> _httpGet(Uri url) async {
    final res = await http.get(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return utf8.decode(res.bodyBytes);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

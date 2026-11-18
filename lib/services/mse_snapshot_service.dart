import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_engine/fundamentals.dart';
import '../models/mse_quote.dart';
import 'mse_service.dart';

/// Вэб хувилбарт зориулсан MSE-ийн өгөгдөл.
///
/// open.mse.mn нь CORS header өгдөггүй тул browser тэр сайтаас шууд уншиж
/// чадахгүй. Иймд GitHub Actions (`.github/workflows/refresh-signals.yml`)
/// өдөр бүр `tool/publish_market.dart`-аар бүх ханшийг татаж Firebase
/// Hosting-д нийтэлдэг бөгөөд вэб апп тэр JSON-оос уншина:
///
/// * `<dataUrl>/market.json` — I–III ангиллын жагсаалт + ханш ([MseSnapshot])
/// * `<dataUrl>/history/<SYMBOL>.json` — сүүлийн ~1 жилийн өдөр тутмын түүх
///
/// Mobile хувилбар хуучнаараа [MseService]-ээр open.mse.mn-ээс шууд уншина.
class MseSnapshotService extends MseService {
  /// `flutter build web --dart-define=MSE_DATA_URL=...`-ээр сольж болно.
  static const String defaultDataUrl = String.fromEnvironment(
    'MSE_DATA_URL',
    defaultValue: 'https://diplom-23056.web.app/mse',
  );

  final String dataUrl;

  /// Нэг удаа татсан snapshot-ийг хэр удаан дахин ашиглах вэ. Provider нь
  /// хувьцаа бүрт [fetchQuote] дууддаг тул энэ хугацаанд дахин татахгүй.
  final Duration maxAge;

  final http.Client Function() _client;
  final DateTime Function() _now;

  MseSnapshotService({
    String? dataUrl,
    super.clientFactory,
    this.maxAge = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : dataUrl = _trimSlash(dataUrl ?? defaultDataUrl),
       _client = clientFactory ?? http.Client.new,
       _now = now ?? DateTime.now;

  MseSnapshot? _snapshot;
  DateTime? _loadedAt;
  Future<MseSnapshot>? _inflight;

  /// Нийтлэгдсэн ханшийг хэзээ татсан бэ (null = хараахан ачаалаагүй).
  DateTime? get generatedAt => _snapshot?.generatedAt;

  Future<MseSnapshot> snapshot({bool force = false}) {
    final cached = _snapshot;
    final loadedAt = _loadedAt;
    if (!force &&
        cached != null &&
        loadedAt != null &&
        _now().difference(loadedAt) < maxAge) {
      return Future.value(cached);
    }
    // Зэрэг ирсэн хүсэлтүүд нэг татал хуваалцана.
    return _inflight ??= _download().whenComplete(() => _inflight = null);
  }

  Future<MseSnapshot> _download() async {
    final body = await _get('$dataUrl/market.json');
    final snap = MseSnapshot.fromJson(jsonDecode(body) as Map<String, dynamic>);
    _snapshot = snap;
    _loadedAt = _now();
    return snap;
  }

  @override
  Future<List<MseSecurity>> fetchSecurities() async {
    final snap = await snapshot();
    if (snap.securities.isEmpty) {
      throw MseException('Нийтлэгдсэн MSE-ийн жагсаалт хоосон байна');
    }
    return snap.securities;
  }

  @override
  Future<MseQuote> fetchQuote(MseSecurity security) async {
    final quote = (await snapshot()).quotes[security.symbol];
    if (quote == null) {
      throw MseException('${security.symbol}: нийтлэгдсэн ханш алга');
    }
    return quote;
  }

  @override
  Future<List<MseDailyBar>> fetchHistory(MseSecurity security) async {
    final snap = await snapshot();
    // III ангиллын хувьцааны түүхийг нийтэлдэггүй (график "хангалтгүй" гэнэ).
    if (!snap.historySymbols.contains(security.symbol)) return [];
    final body = await _get(
      '$dataUrl/history/${Uri.encodeComponent(security.symbol)}.json',
    );
    return [
      for (final row in jsonDecode(body) as List)
        MseDailyBar.fromRow(row as List),
    ]..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Future<List<FinancialReport>> fetchFundamentals(MseSecurity security) =>
      throw MseException('Вэб хувилбарт санхүүгийн тайлан татдаггүй');

  Future<String> _get(String url) async {
    final client = _client();
    try {
      final res = await client
          .get(Uri.parse(url), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw MseException('MSE-ийн нийтлэгдсэн өгөгдөл: HTTP ${res.statusCode}');
      }
      return utf8.decode(res.bodyBytes);
    } finally {
      client.close();
    }
  }

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}

/// `mse/market.json`-ийн агуулга.
class MseSnapshot {
  static const int version = 1;

  final DateTime generatedAt;
  final List<MseSecurity> securities;
  final Map<String, MseQuote> quotes;

  /// `history/<SYMBOL>.json` нийтлэгдсэн хувьцаанууд.
  final Set<String> historySymbols;

  MseSnapshot({
    required this.generatedAt,
    required this.securities,
    required this.quotes,
    required this.historySymbols,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'source': MseService.baseUrl,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'securities': [for (final s in securities) s.toJson()],
    'quotes': [for (final q in quotes.values) q.toJson()],
    'history': historySymbols.toList()..sort(),
  };

  factory MseSnapshot.fromJson(Map<String, dynamic> json) {
    final v = json['version'];
    if (v is! int || v > version) {
      throw MseException('market.json-ийн хувилбар танигдсангүй: $v');
    }
    return MseSnapshot(
      generatedAt:
          DateTime.tryParse('${json['generatedAt']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      securities: [
        for (final s in json['securities'] as List? ?? const [])
          MseSecurity.fromJson(s as Map<String, dynamic>),
      ],
      quotes: {
        for (final q in json['quotes'] as List? ?? const [])
          (q as Map<String, dynamic>)['symbol'] as String: MseQuote.fromJson(q),
      },
      historySymbols: {
        for (final s in json['history'] as List? ?? const []) s as String,
      },
    );
  }
}

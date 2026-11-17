import 'dart:math' as math;

/// Нэг хувьцааны AI дохио — `tool/train_advisor.dart` өдөр бүр тооцоолж
/// `assets/ai/signals.json`-д хадгална. Апп нь энэ жижиг файлыг уншина
/// (хэрэглэгч бүр 4MB түүх татах шаардлагагүй).
class StockSignal {
  final String symbol;
  final String name;
  final int category;

  /// Сүүлийн арилжааны өдөр.
  final DateTime date;
  final double price;

  /// Загварын таамаг: 30 хоногийн дотор ханш өсөх магадлал.
  final double probUp;

  /// Өдрийн хэлбэлзэл (60 өдрийн log өгөөжийн std).
  final double dailyVol;
  final double ret20;
  final double ret60;
  final double drawdown60;
  final double liquidity;
  final double rsi;

  /// Сүүлийн 20 арилжааны өдрийн дундаж арилжааны дүн (₮/өдөр).
  final double avgTurnover;

  /// Ойролцоо салбар (компанийн нэрээр).
  final String sector;

  /// Таамаглалд хамгийн их нөлөөлсөн шинжүүд: нэр -> нөлөө (жин × z-оноо).
  final Map<String, double> drivers;

  /// Шинжүүдийн бодит утга (тайлбарт харуулна).
  final Map<String, double> features;

  const StockSignal({
    required this.symbol,
    required this.name,
    required this.category,
    required this.date,
    required this.price,
    required this.probUp,
    required this.dailyVol,
    required this.ret20,
    required this.ret60,
    required this.drawdown60,
    required this.liquidity,
    required this.rsi,
    this.avgTurnover = 0,
    this.sector = 'Бусад',
    this.drivers = const {},
    this.features = const {},
  });

  /// Жилийн хэлбэлзэл (≈ 250 арилжааны өдөр).
  double get annualVol => dailyVol * math.sqrt(250);

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'name': name,
        'category': category,
        'date': date.toIso8601String().substring(0, 10),
        'price': price,
        'probUp': _r(probUp),
        'dailyVol': _r(dailyVol),
        'ret20': _r(ret20),
        'ret60': _r(ret60),
        'drawdown60': _r(drawdown60),
        'liquidity': _r(liquidity),
        'rsi': _r(rsi),
        'avgTurnover': avgTurnover.roundToDouble(),
        'sector': sector,
        'drivers': {for (final e in drivers.entries) e.key: _r(e.value)},
        'features': {for (final e in features.entries) e.key: _r(e.value)},
      };

  factory StockSignal.fromJson(Map<String, dynamic> j) => StockSignal(
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        category: j['category'] as int,
        date: DateTime.parse(j['date'] as String),
        price: (j['price'] as num).toDouble(),
        probUp: (j['probUp'] as num).toDouble(),
        dailyVol: (j['dailyVol'] as num).toDouble(),
        ret20: (j['ret20'] as num).toDouble(),
        ret60: (j['ret60'] as num).toDouble(),
        drawdown60: (j['drawdown60'] as num).toDouble(),
        liquidity: (j['liquidity'] as num).toDouble(),
        rsi: (j['rsi'] as num).toDouble(),
        avgTurnover: (j['avgTurnover'] as num?)?.toDouble() ?? 0,
        sector: j['sector'] as String? ?? 'Бусад',
        drivers: {
          for (final e in (j['drivers'] as Map? ?? {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
        features: {
          for (final e in (j['features'] as Map? ?? {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
      );

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;
}

/// Бүх хувьцааны дохио + хоорондын корреляци + загварын мэдээлэл.
class SignalSet {
  final DateTime generatedAt;
  final List<StockSignal> signals;

  /// Хувьцаа хоорондын өдрийн өгөөжийн корреляци (сүүлийн ~1 жил).
  final List<String> corrSymbols;
  final List<List<double>> correlation;

  /// Загварын тестийн үзүүлэлтүүд (AUC, backtest гэх мэт).
  final Map<String, dynamic> modelMetrics;

  const SignalSet({
    required this.generatedAt,
    required this.signals,
    this.corrSymbols = const [],
    this.correlation = const [],
    this.modelMetrics = const {},
  });

  StockSignal? signalFor(String symbol) {
    for (final s in signals) {
      if (s.symbol == symbol) return s;
    }
    return null;
  }

  /// Хоёр хувьцааны корреляци. Мэдэгдэхгүй бол болгоомжтой 0.3 гэж үзнэ.
  double correlationOf(String a, String b) {
    if (a == b) return 1;
    final i = corrSymbols.indexOf(a), j = corrSymbols.indexOf(b);
    if (i < 0 || j < 0) return 0.3;
    return correlation[i][j];
  }

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toIso8601String(),
        'modelMetrics': modelMetrics,
        'signals': signals.map((s) => s.toJson()).toList(),
        'correlation': {
          'symbols': corrSymbols,
          'matrix': [
            for (final row in correlation)
              [for (final v in row) (v * 1000).roundToDouble() / 1000]
          ],
        },
      };

  factory SignalSet.fromJson(Map<String, dynamic> j) {
    final corr = j['correlation'] as Map? ?? {};
    return SignalSet(
      generatedAt: DateTime.parse(j['generatedAt'] as String),
      modelMetrics: Map<String, dynamic>.from(j['modelMetrics'] as Map? ?? {}),
      signals: [
        for (final s in j['signals'] as List)
          StockSignal.fromJson(s as Map<String, dynamic>)
      ],
      corrSymbols: List<String>.from(corr['symbols'] as List? ?? []),
      correlation: [
        for (final row in corr['matrix'] as List? ?? [])
          [for (final v in row as List) (v as num).toDouble()]
      ],
    );
  }
}

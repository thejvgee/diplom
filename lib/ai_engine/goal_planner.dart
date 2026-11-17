import 'dart:math' as math;

/// Зорилгын төлөвлөгчийн зах зээлийн таамаглал.
class MarketAssumptions {
  /// Хувьцааны сарын дундаж (арифметик) өгөөж.
  final double stockMonthlyMean;

  /// Хувьцааны сарын хэлбэлзэл.
  final double stockMonthlyVol;

  /// Хадгаламжийн жилийн хүү (бэлэн мөнгөний хэсэгт).
  final double cashAnnualRate;

  /// Жилийн инфляци — үр дүнг өнөөгийн мөнгөний үнэ цэнээр харуулна.
  final double inflationAnnual;

  /// Хувьцааны хэсгийн жилийн зардал (шимтгэл, тэнцвэржүүлэлт).
  final double annualFee;

  /// MSE-ийн түүхэн сарын өгөөж (bootstrap-д). null бол лог-нормаль.
  final List<double>? monthlySeries;

  /// Түүхэн өгөгдлийн хугацаа (тайлбарт).
  final String source;

  /// MSE-ийн олон хувьцаа ховор арилжаалагддаг тул сарын өгөөжийн хэлбэлзэл
  /// бодит байдлаас доогуур гардаг. 6–10 хувьцаатай багцын хувьд болгоомжтой
  /// байх үүднээс жилийн хэлбэлзлийн доод хязгаар тавина.
  static const double minAnnualVol = 0.20;

  const MarketAssumptions({
    required this.stockMonthlyMean,
    required this.stockMonthlyVol,
    required this.cashAnnualRate,
    this.inflationAnnual = 0,
    this.annualFee = 0,
    this.monthlySeries,
    this.source = '',
  });

  /// `signals.json`-ийн `modelMetrics.market`-аас (tool/train_advisor.dart).
  factory MarketAssumptions.fromMetrics(
    Map<String, dynamic>? market, {
    double cashAnnualRate = 0.10,
    double inflationAnnual = 0,
    double annualFee = 0,
  }) {
    final mean = (market?['monthlyMean'] as num?)?.toDouble() ?? 0.0075;
    final vol = (market?['monthlyVol'] as num?)?.toDouble() ?? 0.03;
    final series = market?['monthlySeries'];
    return MarketAssumptions(
      stockMonthlyMean: mean,
      stockMonthlyVol: math.max(vol, minAnnualVol / math.sqrt(12)),
      cashAnnualRate: cashAnnualRate,
      inflationAnnual: inflationAnnual,
      annualFee: annualFee,
      monthlySeries: series is List && series.length >= 24
          ? [for (final v in series) (v as num).toDouble()]
          : null,
      source: market == null
          ? 'анхдагч таамаглал'
          : 'MSE ${market['since']}-аас хойшх ${market['months']} сар',
    );
  }

  bool get usesBootstrap => monthlySeries != null;
  double get stockAnnualReturn => math.pow(1 + stockMonthlyMean, 12) - 1;
  double get stockAnnualVol => stockMonthlyVol * math.sqrt(12);
}

/// "N жилд X төгрөг хуримтлуулах" зорилгыг Monte Carlo аргаар тооцоолно.
///
/// * Хувьцааны өгөөж: MSE-ийн түүхэн сарын өгөөжөөс 3 сарын блокоор
///   санамсаргүй сонгоно (block bootstrap) — огцом уналт, үргэлжилсэн өсөлтийг
///   бодитоор дуурайна. Хэлбэлзлийг доод хязгаар хүртэл өргөтгөнө.
/// * Инфляцийг хасаж бүх дүнг өнөөгийн мөнгөний үнэ цэнээр тооцно.
/// * Glide path: зорилгод ойртох тусам хувьцааны хувийг бууруулна.
/// Эцсийн хөрөнгө c-ээс шугаман хамаардаг: W = A + c·B (зам бүрт), тиймээс
/// шаардлагатай c-г дахин симуляц хийлгүйгээр шууд олно.
class GoalPlanner {
  final MarketAssumptions assumptions;
  final int paths;
  final int seed;

  /// Bootstrap-ийн блокын урт (сар).
  static const int blockMonths = 3;

  const GoalPlanner(this.assumptions, {this.paths = 2000, this.seed = 42});

  /// [glidePath] үед сүүлийн хэдэн жилд хувьцааны хувийг [stockShare]-аас
  /// max(0.2, stockShare − 0.4) хүртэл шугаман бууруулна.
  static double stockShareAt(
      int month, int months, double stockShare, bool glidePath) {
    if (!glidePath) return stockShare;
    final glideMonths = math.min(36, months);
    final start = months - glideMonths;
    if (month < start) return stockShare;
    final end = math.max(0.2, stockShare - 0.4);
    if (end >= stockShare) return stockShare;
    final t = (month - start + 1) / glideMonths;
    return stockShare + (end - stockShare) * t;
  }

  GoalPlan plan({
    required double target,
    required int years,
    required double initial,
    required double stockShare,
    bool glidePath = false,
  }) {
    if (target <= 0) throw ArgumentError('Зорилтот дүн 0-ээс их байх ёстой');
    final y = years.clamp(1, 40);
    final months = y * 12;
    final w0 = stockShare.clamp(0.0, 1.0);
    final a0 = math.max(0.0, initial);
    final a = assumptions;

    final cashMonthly = math.pow(1 + a.cashAnnualRate, 1 / 12) - 1;
    final inflMonthly = math.pow(1 + a.inflationAnnual, 1 / 12) - 1;
    final feeMonthly = a.annualFee / 12;

    // Лог-нормаль параметр (bootstrap байхгүй үед)
    final m = a.stockMonthlyMean;
    final s = a.stockMonthlyVol;
    final sigma2 = math.log(1 + (s * s) / ((1 + m) * (1 + m)));
    final sigma = math.sqrt(sigma2);
    final mu = math.log(1 + m) - sigma2 / 2;

    // Bootstrap цуврал: дунджийг хадгалж хэлбэлзлийг доод хязгаар хүртэл өргөтгөнө
    List<double>? series;
    if (a.monthlySeries != null) {
      final raw = a.monthlySeries!;
      final mean = raw.reduce((x, y) => x + y) / raw.length;
      final sd = math.sqrt(
          raw.map((r) => (r - mean) * (r - mean)).reduce((x, y) => x + y) /
              (raw.length - 1));
      final k = sd > 0 ? math.max(1.0, s / sd) : 1.0;
      series = [for (final r in raw) math.max(-0.95, mean + (r - mean) * k)];
    }

    final rnd = math.Random(seed);
    double? spare;
    double normal() {
      if (spare != null) {
        final v = spare!;
        spare = null;
        return v;
      }
      final u1 = math.max(rnd.nextDouble(), 1e-12);
      final u2 = rnd.nextDouble();
      final r = math.sqrt(-2 * math.log(u1));
      spare = r * math.sin(2 * math.pi * u2);
      return r * math.cos(2 * math.pi * u2);
    }

    final shares = [
      for (var t = 0; t < months; t++) stockShareAt(t, months, w0, glidePath)
    ];

    final yearlyA = List.generate(paths, (_) => List<double>.filled(y + 1, 0));
    final yearlyB = List.generate(paths, (_) => List<double>.filled(y + 1, 0));
    for (var p = 0; p < paths; p++) {
      var av = a0, bv = 0.0;
      yearlyA[p][0] = av;
      var blockPos = blockMonths;
      var blockStart = 0;
      for (var t = 0; t < months; t++) {
        double stock;
        if (series != null) {
          if (blockPos >= blockMonths) {
            blockStart = rnd.nextInt(series.length);
            blockPos = 0;
          }
          stock = series[(blockStart + blockPos) % series.length];
          blockPos++;
        } else {
          stock = math.exp(mu + sigma * normal()) - 1;
        }
        final w = shares[t];
        final nominal = 1 + w * (stock - feeMonthly) + (1 - w) * cashMonthly;
        final g = nominal / (1 + inflMonthly); // бодит (өнөөгийн мөнгөөр)
        av *= g;
        bv = (bv + 1) * g;
        if ((t + 1) % 12 == 0) {
          yearlyA[p][(t + 1) ~/ 12] = av;
          yearlyB[p][(t + 1) ~/ 12] = bv;
        }
      }
    }

    return GoalPlan._(
      target: target,
      years: y,
      initial: a0,
      stockShare: w0,
      finalStockShare: shares.last,
      glidePath: glidePath,
      assumptions: assumptions,
      yearlyA: yearlyA,
      yearlyB: yearlyB,
    );
  }
}

class GoalPlan {
  final double target;
  final int years;
  final double initial;
  final double stockShare;
  final double finalStockShare;
  final bool glidePath;
  final MarketAssumptions assumptions;
  final List<List<double>> _a;
  final List<List<double>> _b;

  /// Зам бүрт зорилгод хүрэхэд шаардлагатай хамгийн бага сарын хуримтлал (өсөхөөр эрэмбэлсэн).
  late final List<double> _requiredPerPath = () {
    final list = <double>[];
    for (var p = 0; p < _a.length; p++) {
      final a = _a[p][years], b = _b[p][years];
      list.add(a >= target ? 0.0 : (b <= 0 ? double.infinity : (target - a) / b));
    }
    return list..sort();
  }();

  GoalPlan._({
    required this.target,
    required this.years,
    required this.initial,
    required this.stockShare,
    required this.finalStockShare,
    required this.glidePath,
    required this.assumptions,
    required List<List<double>> yearlyA,
    required List<List<double>> yearlyB,
  })  : _a = yearlyA,
        _b = yearlyB;

  int get months => years * 12;

  /// [confidence] магадлалтай (жишээ нь 0.8 = 80%) хүрэхэд сард хэдийг нэмэх вэ.
  double requiredMonthly(double confidence) {
    final q = confidence.clamp(0.0, 1.0);
    final i = ((_requiredPerPath.length - 1) * q).ceil();
    return _requiredPerPath[i];
  }

  /// Сард [monthly] төгрөг нэмбэл зорилгод хүрэх магадлал.
  double probability(double monthly) {
    var lo = 0, hi = _requiredPerPath.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_requiredPerPath[mid] <= monthly) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo / _requiredPerPath.length;
  }

  /// Жил бүрийн эцэст хөрөнгийн [percentiles] (жишээ нь 0.1, 0.5, 0.9).
  List<List<double>> bands(double monthly,
      {List<double> percentiles = const [0.1, 0.5, 0.9]}) {
    final out = [for (final _ in percentiles) List<double>.filled(years + 1, 0)];
    for (var k = 0; k <= years; k++) {
      final values = [
        for (var p = 0; p < _a.length; p++) _a[p][k] + monthly * _b[p][k]
      ]..sort();
      for (var j = 0; j < percentiles.length; j++) {
        out[j][k] = values[((values.length - 1) * percentiles[j]).round()];
      }
    }
    return out;
  }

  /// Хамгийн муу 10% хувилбарын дундаж эцсийн дүн (CVaR) — эрсдэлийн хэмжүүр.
  double worstTenPercent(double monthly) {
    final values = [
      for (var p = 0; p < _a.length; p++) _a[p][years] + monthly * _b[p][years]
    ]..sort();
    final n = math.max(1, values.length ~/ 10);
    return values.take(n).reduce((a, b) => a + b) / n;
  }

  /// Нийт хийх хуримтлал (эхний мөнгө + сар бүрийнх).
  double totalContributed(double monthly) => initial + monthly * months;
}

import 'dart:math' as math;

/// Зорилгын төлөвлөгчийн зах зээлийн таамаглал.
class MarketAssumptions {
  /// Хувьцааны сарын дундаж (арифметик) өгөөж.
  final double stockMonthlyMean;

  /// Хувьцааны сарын хэлбэлзэл.
  final double stockMonthlyVol;

  /// Хадгаламжийн жилийн хүү (бэлэн мөнгөний хэсэгт).
  final double cashAnnualRate;

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
    this.source = '',
  });

  /// `signals.json`-ийн `modelMetrics.market`-аас (tool/train_advisor.dart).
  factory MarketAssumptions.fromMetrics(
    Map<String, dynamic>? market, {
    double cashAnnualRate = 0.10,
  }) {
    final mean = (market?['monthlyMean'] as num?)?.toDouble() ?? 0.0075;
    final vol = (market?['monthlyVol'] as num?)?.toDouble() ?? 0.03;
    return MarketAssumptions(
      stockMonthlyMean: mean,
      stockMonthlyVol: math.max(vol, minAnnualVol / math.sqrt(12)),
      cashAnnualRate: cashAnnualRate,
      source: market == null
          ? 'анхдагч таамаглал'
          : 'MSE ${market['since']}-аас хойшх ${market['months']} сар',
    );
  }

  double get stockAnnualReturn => math.pow(1 + stockMonthlyMean, 12) - 1;
  double get stockAnnualVol => stockMonthlyVol * math.sqrt(12);
}

/// "N жилд X төгрөг хуримтлуулах" зорилгыг Monte Carlo аргаар тооцоолно.
///
/// Багц сар бүр [stockShare] хувь хувьцаа (лог-нормаль өгөөж), үлдсэнийг
/// хадгаламжинд байлгаж тэнцвэржүүлнэ. Сар бүрийн эхэнд c төгрөг нэмнэ.
/// Эцсийн хөрөнгө c-ээс шугаман хамаардаг: W = A + c·B (зам бүрт), тиймээс
/// шаардлагатай c-г дахин симуляц хийлгүйгээр шууд олно.
class GoalPlanner {
  final MarketAssumptions assumptions;
  final int paths;
  final int seed;

  const GoalPlanner(this.assumptions, {this.paths = 2000, this.seed = 42});

  GoalPlan plan({
    required double target,
    required int years,
    required double initial,
    required double stockShare,
  }) {
    if (target <= 0) throw ArgumentError('Зорилтот дүн 0-ээс их байх ёстой');
    final y = years.clamp(1, 40);
    final months = y * 12;
    final w = stockShare.clamp(0.0, 1.0);
    final a0 = math.max(0.0, initial);

    final m = assumptions.stockMonthlyMean;
    final s = assumptions.stockMonthlyVol;
    final sigma2 = math.log(1 + (s * s) / ((1 + m) * (1 + m)));
    final sigma = math.sqrt(sigma2);
    final mu = math.log(1 + m) - sigma2 / 2;
    final cashMonthly = math.pow(1 + assumptions.cashAnnualRate, 1 / 12) - 1;

    final rnd = math.Random(seed);
    double? spare;
    double normal() {
      // Box–Muller
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

    // yearlyA[p][k], yearlyB[p][k]: k-р жилийн эцсийн хөрөнгө = A + c·B
    final yearlyA = List.generate(paths, (_) => List<double>.filled(y + 1, 0));
    final yearlyB = List.generate(paths, (_) => List<double>.filled(y + 1, 0));
    for (var p = 0; p < paths; p++) {
      var a = a0, b = 0.0;
      yearlyA[p][0] = a;
      for (var t = 0; t < months; t++) {
        final stock = math.exp(mu + sigma * normal()) - 1;
        final g = 1 + w * stock + (1 - w) * cashMonthly;
        a *= g;
        b = (b + 1) * g;
        if ((t + 1) % 12 == 0) {
          yearlyA[p][(t + 1) ~/ 12] = a;
          yearlyB[p][(t + 1) ~/ 12] = b;
        }
      }
    }

    return GoalPlan._(
      target: target,
      years: y,
      initial: a0,
      stockShare: w,
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

  /// Нийт хийх хуримтлал (эхний мөнгө + сар бүрийнх).
  double totalContributed(double monthly) => initial + monthly * months;
}

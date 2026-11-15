import 'dart:math' as math;

import 'risk_profile.dart';
import 'signals.dart';

/// Gemini-гүй, утсан дээр ажилладаг хөрөнгө оруулалтын зөвлөх.
///
/// 1. Багцын эрүүл мэнд: төрөлжилт, эрсдэл, бэлэн мөнгө, дохио, хөрвөх чадвар.
/// 2. Хуваарилалт: эрсдэлийн профайлд тохируулан загварын дохио ба
///    хэлбэлзэлд суурилж хувьцаа сонгоно (корреляци өндөртэйг давхардуулахгүй).
/// 3. Зөвлөгөө: одоогийн багцыг зорилтот хуваарилалттай харьцуулж
///    авах/зарах/барих санал, шалтгааныг монголоор тайлбарлана.
class AdvisorEngine {
  final SignalSet signals;

  /// Дохио хэт хуучирсан бол (жишээ нь удаан арилжаагүй) ашиглахгүй.
  static const int maxSignalAgeDays = 45;

  /// Үүнээс бага зөрүүтэй бол "барих" гэж үзнэ (нийт хөрөнгийн хувиар).
  static const double rebalanceThreshold = 0.02;

  static const String disclaimer =
      'Энэ нь түүхэн өгөгдөлд суурилсан автомат шинжилгээ бөгөөд санхүүгийн '
      'мэргэжлийн зөвлөгөө биш. Хөрөнгө оруулалт эрсдэлтэй тул шийдвэрээ '
      'өөрөө гаргана уу.';

  const AdvisorEngine(this.signals);

  /// Сургалтын өгөгдөлд хувьцаа 30 хоногт өссөн дундаж хувь. Загварын
  /// магадлалыг үүнтэй харьцуулж "дунджаас сайн/муу" гэж дүгнэнэ.
  double get baseRate =>
      (signals.modelMetrics['baseRateUp'] as num?)?.toDouble() ?? 0.5;

  /// Дунджаас хэр илүү (эерэг = сайн).
  double edgeOf(StockSignal s) => s.probUp - baseRate;

  AdvisorReport analyze({
    required List<HoldingInput> holdings,
    required double cash,
    required RiskProfile profile,
    Map<String, double> livePrices = const {},
  }) {
    double priceOf(String symbol, [double fallback = 0]) {
      final live = livePrices[symbol];
      if (live != null && live > 0) return live;
      if (fallback > 0) return fallback;
      return signals.signalFor(symbol)?.price ?? 0;
    }

    // --- Одоогийн байдал ---------------------------------------------------
    final positions = <String, double>{}; // symbol -> үнэлгээ (₮)
    final quantities = <String, double>{};
    for (final h in holdings) {
      if (h.quantity <= 0) continue;
      final p = priceOf(h.symbol, h.currentPrice > 0 ? h.currentPrice : h.averageCost);
      positions[h.symbol] = (positions[h.symbol] ?? 0) + h.quantity * p;
      quantities[h.symbol] = (quantities[h.symbol] ?? 0) + h.quantity;
    }
    final invested = positions.values.fold<double>(0, (a, b) => a + b);
    final total = invested + math.max(0, cash);
    final currentW = {
      for (final e in positions.entries) e.key: total > 0 ? e.value / total : 0.0
    };

    final health = _health(currentW, total, cash, profile);

    // --- Зорилтот хуваарилалт ----------------------------------------------
    final targets = _allocate(profile);
    final targetW = {for (final t in targets) t.symbol: t.weight};

    // --- Зөвлөгөө -----------------------------------------------------------
    final suggestions = <Suggestion>[];
    final symbols = {...currentW.keys, ...targetW.keys};
    for (final symbol in symbols) {
      final cur = currentW[symbol] ?? 0;
      final tgt = targetW[symbol] ?? 0;
      final diff = tgt - cur;
      final price = priceOf(symbol);
      final sig = signals.signalFor(symbol);
      final reason = _explain(sig, profile);

      if (cur > 0 && tgt == 0) {
        final qty = quantities[symbol] ?? 0;
        final weak = sig == null || edgeOf(sig) < -0.03;
        final why = _exclusionReason(sig, profile);
        if (weak || why != null) {
          suggestions.add(Suggestion(
            type: SuggestionType.sell,
            symbol: symbol,
            action: '$symbol — зарах (${_fmtQty(qty)} ширхэг)',
            reasoning: [
              if (why != null) why,
              reason,
            ].join(' '),
            amount: cur * total,
            shares: qty,
          ));
        } else {
          suggestions.add(Suggestion(
            type: SuggestionType.hold,
            symbol: symbol,
            action: '$symbol — барих',
            reasoning: 'Дохио төвийг сахисан тул шинээр нэмэхгүй ч яаралтай '
                'зарах шаардлагагүй. $reason',
            amount: 0,
          ));
        }
      } else if (diff > rebalanceThreshold && price > 0) {
        final amount = diff * total;
        final shares = (amount / price).floorToDouble();
        if (shares < 1) continue;
        suggestions.add(Suggestion(
          type: SuggestionType.buy,
          symbol: symbol,
          action: '$symbol — ${_fmtQty(shares)} ширхэг авах (~${_fmtMoney(shares * price)}₮)',
          reasoning: 'Зорилтот жин ${_pct(tgt)} (одоо ${_pct(cur)}). $reason',
          amount: shares * price,
          shares: shares,
        ));
      } else if (diff < -rebalanceThreshold && price > 0) {
        final amount = -diff * total;
        final shares = math.min(
            (amount / price).floorToDouble(), quantities[symbol] ?? 0);
        if (shares < 1) continue;
        suggestions.add(Suggestion(
          type: SuggestionType.sell,
          symbol: symbol,
          action: '$symbol — ${_fmtQty(shares)} ширхэг зарж бууруулах',
          reasoning: 'Нэг хувьцаанд хэт төвлөрсөн: жин ${_pct(cur)}, '
              '${profile.label} профайлд ${_pct(tgt)} зохимжтой. $reason',
          amount: shares * price,
          shares: shares,
        ));
      } else if (cur > 0) {
        suggestions.add(Suggestion(
          type: SuggestionType.hold,
          symbol: symbol,
          action: '$symbol — барих',
          reasoning: 'Жин нь зорилтот түвшинд ойр (${_pct(cur)}). $reason',
          amount: 0,
        ));
      }
    }

    final cashW = total > 0 ? math.max(0, cash) / total : 1.0;
    final targetCashW = 1 - targets.fold<double>(0, (a, t) => a + t.weight);
    if ((cashW - targetCashW).abs() > 0.1) {
      suggestions.add(Suggestion(
        type: SuggestionType.allocate,
        symbol: '',
        action: cashW > targetCashW
            ? 'Бэлэн мөнгөний хэсгийг хөрөнгө оруулалтад шилжүүлэх'
            : 'Бэлэн мөнгөний нөөцөө нэмэгдүүлэх',
        reasoning: 'Одоо бэлэн мөнгө ${_pct(cashW)}, ${profile.label} '
            'профайлд ойролцоогоор ${_pct(targetCashW)} байхад зохимжтой. '
            'Бэлэн мөнгө нь уналтын үед хамгаалалт болохоос гадна шинэ '
            'боломжид ашиглагдана.',
        amount: (cashW - targetCashW).abs() * total,
      ));
    }

    const order = {
      SuggestionType.sell: 0,
      SuggestionType.buy: 1,
      SuggestionType.allocate: 2,
      SuggestionType.hold: 3,
    };
    suggestions.sort((a, b) {
      final o = order[a.type]!.compareTo(order[b.type]!);
      return o != 0 ? o : b.amount.compareTo(a.amount);
    });

    final overview = StringBuffer()
      ..write('Таны багцын нийт үнэлгээ ${_fmtMoney(total)}₮, үүнээс '
          '${_pct(cashW)} нь бэлэн мөнгө. ')
      ..write('Багцын эрүүл мэндийн оноо ${health.score}/100. ')
      ..write(targets.isEmpty
          ? 'Одоогоор ${profile.label} профайлын шалгуурыг хангасан эерэг '
              'дохиотой хувьцаа олдсонгүй тул бэлэн мөнгөө хадгалахыг зөвлөж байна.'
          : '${profile.label} профайлд тохируулан ${targets.length} хувьцаанд '
              'нийт хөрөнгийн ${_pct(1 - targetCashW)}-ийг хуваарилахыг санал '
              'болгож байна.');

    return AdvisorReport(
      profile: profile,
      health: health,
      targets: targets,
      suggestions: suggestions,
      overview: overview.toString(),
      totalValue: total,
      signalsDate: signals.generatedAt,
      modelMetrics: signals.modelMetrics,
    );
  }

  // ---------------------------------------------------------------------------

  /// Багцын жилийн хэлбэлзэл: σp = √(Σ Σ wᵢ wⱼ σᵢ σⱼ ρᵢⱼ).
  double portfolioVolatility(Map<String, double> weights) {
    final syms = weights.keys.toList();
    var variance = 0.0;
    for (final a in syms) {
      for (final b in syms) {
        final sa = signals.signalFor(a)?.annualVol ?? 0.5;
        final sb = signals.signalFor(b)?.annualVol ?? 0.5;
        variance += weights[a]! * weights[b]! * sa * sb * signals.correlationOf(a, b);
      }
    }
    return math.sqrt(math.max(0, variance));
  }

  PortfolioHealth _health(
    Map<String, double> w,
    double total,
    double cash,
    RiskProfile profile,
  ) {
    final strengths = <String>[];
    final weaknesses = <String>[];
    final cashW = total > 0 ? math.max(0, cash) / total : 1.0;
    final stockW = w.values.fold<double>(0, (a, b) => a + b);

    if (w.isEmpty) {
      return PortfolioHealth(
        score: 50,
        annualVol: 0,
        effectivePositions: 0,
        cashWeight: cashW,
        strengths: ['Эрсдэлгүй: бүх хөрөнгө бэлэн мөнгөөр байна.'],
        weaknesses: [
          'Хувьцаа байхгүй тул хөрөнгө өсөх боломжгүй, инфляцид үнэ цэнээ алдана.'
        ],
      );
    }

    // Төрөлжилт — Herfindahl индексийн урвуу = "үр ашигт хувьцааны тоо"
    final hhi = w.values.fold<double>(0, (a, v) => a + (v / stockW) * (v / stockW));
    final effN = 1 / hhi;
    final top = w.entries.reduce((a, b) => a.value > b.value ? a : b);
    // Хувьцааны хэсэг маш бага бол төрөлжилт чухал биш (төвийг сахисан оноо)
    final divScore =
        stockW < 0.1 ? 15.0 : 30 * math.min(1.0, (effN - 1) / 5);
    if (top.value > profile.maxWeight * 1.2) {
      weaknesses.add('Төвлөрөл өндөр: ${top.key} нийт хөрөнгийн '
          '${_pct(top.value)}-ийг эзэлж байна (${profile.label} профайлд '
          '${_pct(profile.maxWeight)}-аас ихгүй байх нь зүйтэй).');
    } else if (stockW >= 0.2 && effN < 3) {
      weaknesses.add('Цөөн хувьцаанд төвлөрсөн: үр ашигт хувьцааны тоо '
          '${effN.toStringAsFixed(1)}.');
    } else if (effN >= 5 && stockW >= 0.1) {
      strengths.add('Сайн төрөлжсөн: ${effN.toStringAsFixed(1)} хувьцаанд '
          'тэнцвэртэй хуваарилсан.');
    }

    // Эрсдэл
    final vol = portfolioVolatility(w);
    final allowedVol = profile.maxAnnualVol * (1 - profile.targetCash);
    final volScore = vol <= allowedVol
        ? 30.0
        : 30 * math.max(0.0, 1 - (vol - allowedVol) / allowedVol);
    if (vol <= allowedVol) {
      strengths.add('Багцын жилийн хэлбэлзэл ${_pct(vol)} нь ${profile.label} профайлд тохирно.');
    } else {
      weaknesses.add('Багцын жилийн хэлбэлзэл ${_pct(vol)} нь ${profile.label} '
          'профайлын хязгаар ${_pct(allowedVol)}-аас өндөр.');
    }

    // Бэлэн мөнгө
    final cashDev = (cashW - profile.targetCash).abs();
    final cashScore = 15 * math.max(0.0, 1 - math.max(0, cashDev - 0.1) / 0.3);
    if (cashDev > 0.15) {
      weaknesses.add(cashW > profile.targetCash
          ? 'Бэлэн мөнгө ${_pct(cashW)} — хэт их хувь нь ажиллахгүй байна.'
          : 'Бэлэн мөнгө ${_pct(cashW)} — уналтын үеийн нөөц бага.');
    }

    // Дохио (жигнэсэн дундаж өсөх магадлал)
    var probSum = 0.0, liqSum = 0.0, known = 0.0;
    final weak = <String>[];
    for (final e in w.entries) {
      final s = signals.signalFor(e.key);
      if (s == null) continue;
      probSum += s.probUp * e.value;
      liqSum += s.liquidity * e.value;
      known += e.value;
      if (edgeOf(s) < -0.03) weak.add(e.key);
    }
    final avgProb = known > 0 ? probSum / known : 0.5;
    final avgLiq = known > 0 ? liqSum / known : 1.0;
    final avgEdge = avgProb - baseRate;
    final sigScore = 15 * ((avgEdge + 0.05) / 0.1).clamp(0.0, 1.0);
    if (avgEdge >= 0.02) {
      strengths.add('Багцын хувьцаануудын дундаж өсөх магадлал ${_pct(avgProb)} '
          'нь зах зээлийн дунджаас (${_pct(baseRate)}) өндөр.');
    }
    if (weak.isNotEmpty) {
      weaknesses.add('Сул дохиотой хувьцаа: ${weak.join(', ')}.');
    }

    // Хөрвөх чадвар
    final liqScore = 10 * (avgLiq / profile.minLiquidity).clamp(0.0, 1.0);
    if (avgLiq < profile.minLiquidity) {
      weaknesses.add('Зарим хувьцаа ховор арилжаалагддаг тул хэрэгтэй үедээ '
          'зарахад хэцүү байж болно.');
    }

    return PortfolioHealth(
      score: (divScore + volScore + cashScore + sigScore + liqScore).round().clamp(0, 100),
      annualVol: vol,
      effectivePositions: effN,
      cashWeight: cashW,
      strengths: strengths,
      weaknesses: weaknesses,
    );
  }

  List<AllocationTarget> _allocate(RiskProfile profile) {
    final newest = signals.signals.isEmpty
        ? DateTime.now()
        : signals.signals.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);

    final candidates = signals.signals
        .where((s) =>
            _exclusionReason(s, profile) == null &&
            newest.difference(s.date).inDays <= maxSignalAgeDays)
        .toList();
    double score(StockSignal s) =>
        edgeOf(s) / math.pow(math.max(s.annualVol, 0.05), profile.volPenalty);
    candidates.sort((a, b) => score(b).compareTo(score(a)));

    // Шунахай сонголт: өндөр корреляцитай хувьцааг давхардуулахгүй
    final picked = <StockSignal>[];
    for (final c in candidates) {
      if (picked.length >= profile.maxPositions) break;
      final tooSimilar = picked.any((p) => signals.correlationOf(p.symbol, c.symbol) > 0.8);
      if (!tooSimilar) picked.add(c);
    }
    if (picked.isEmpty) return [];

    // Оноонд пропорциональ жин, дээд хязгаараар таслаад илүүг дахин хуваана
    final investable = 1 - profile.targetCash;
    final raw = {for (final p in picked) p.symbol: score(p)};
    final weights = <String, double>{};
    var remaining = investable;
    var free = Map.of(raw);
    while (free.isNotEmpty && remaining > 1e-9) {
      final sum = free.values.fold<double>(0, (a, b) => a + b);
      final capped = <String>[];
      for (final e in free.entries) {
        final w = remaining * e.value / sum;
        if (w >= profile.maxWeight) capped.add(e.key);
      }
      if (capped.isEmpty) {
        for (final e in free.entries) {
          weights[e.key] = remaining * e.value / sum;
        }
        break;
      }
      for (final k in capped) {
        weights[k] = profile.maxWeight;
        remaining -= profile.maxWeight;
        free.remove(k);
      }
      free = Map.of(free);
    }

    return [
      for (final p in picked)
        if ((weights[p.symbol] ?? 0) > 0)
          AllocationTarget(
            symbol: p.symbol,
            name: p.name,
            weight: weights[p.symbol]!,
            signal: p,
          ),
    ]..sort((a, b) => b.weight.compareTo(a.weight));
  }

  /// Хувьцааг профайлд оруулахгүй шалтгаан (null = тэнцэнэ).
  String? _exclusionReason(StockSignal? s, RiskProfile profile) {
    if (s == null) return 'Энэ хувьцааны хангалттай арилжааны түүх алга.';
    if (s.liquidity < profile.minLiquidity) {
      return 'Ховор арилжаалагддаг (хөрвөх чадвар ${_pct(s.liquidity)}).';
    }
    if (s.annualVol > profile.maxAnnualVol) {
      return 'Хэлбэлзэл ${_pct(s.annualVol)} нь ${profile.label} профайлд хэт өндөр.';
    }
    if (edgeOf(s) <= 0.02) {
      return 'Дохио сул: өсөх магадлал зах зээлийн дунджаас илүү биш.';
    }
    return null;
  }

  /// Шинжийн бодит утгыг ойлгомжтой текст болгох.
  static String describeFeature(String name, double v) {
    String signed(double x) => '${x >= 0 ? '+' : ''}${_pct(x)}';
    switch (name) {
      case 'ret5':
        return '5 өдрийн өгөөж ${signed(v)}';
      case 'ret20':
        return '20 өдрийн өгөөж ${signed(v)}';
      case 'ret60':
        return '60 өдрийн өгөөж ${signed(v)}';
      case 'vol20':
        return '20 өдрийн хэлбэлзэл ${_pct(v * math.sqrt(250))}';
      case 'vol60':
        return '60 өдрийн хэлбэлзэл ${_pct(v * math.sqrt(250))}';
      case 'rsi14':
        return 'RSI ${((v + 0.5) * 100).toStringAsFixed(0)}';
      case 'ma20gap':
        return 'ханш 20 өдрийн дунджаас ${signed(v)}';
      case 'ma60gap':
        return 'ханш 60 өдрийн дунджаас ${signed(v)}';
      case 'dd60':
        return '60 өдрийн оргилоос ${signed(v)}';
      case 'volumeRatio':
        return 'арилжааны идэвх ×${math.exp(v).toStringAsFixed(1)}';
      case 'liquidity':
        return 'хөрвөх чадвар ${_pct(v)}';
    }
    return name;
  }

  /// Дохиог монгол хэлээр тайлбарлана (бодит тоотой).
  String explainSignal(StockSignal? s) => _explain(s);

  String _explain(StockSignal? s, [RiskProfile? profile]) {
    if (s == null) return '';
    final drivers = s.drivers.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final top = drivers.take(2).map((e) {
      final value = s.features[e.key];
      final what = value == null ? e.key : describeFeature(e.key, value);
      return '$what (магадлалыг ${e.value >= 0 ? '↑ өсгөсөн' : '↓ бууруулсан'})';
    }).join('; ');
    final edge = edgeOf(s);
    return 'Загварын тооцоолсноор 30 хоногт өсөх магадлал ${_pct(s.probUp)} '
        '(дунджаас ${edge >= 0 ? '+' : ''}${(edge * 100).toStringAsFixed(1)} пункт); '
        'сүүлийн 60 өдөрт ${s.ret60 >= 0 ? '+' : ''}${_pct(s.ret60)}, '
        'жилийн хэлбэлзэл ${_pct(s.annualVol)}.'
        '${top.isEmpty ? '' : ' Гол хүчин зүйл: $top.'}';
  }

  static String _pct(num v) => '${(v * 100).toStringAsFixed(v.abs() < 0.1 ? 1 : 0)}%';
  static String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
  static String _fmtMoney(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0 && s[i - 1] != '-') b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class HoldingInput {
  final String symbol;
  final double quantity;
  final double averageCost;
  final double currentPrice;
  const HoldingInput({
    required this.symbol,
    required this.quantity,
    required this.averageCost,
    this.currentPrice = 0,
  });
}

enum SuggestionType { buy, sell, hold, allocate }

class Suggestion {
  final SuggestionType type;
  final String symbol;
  final String action;
  final String reasoning;
  final double amount;
  final double shares;
  const Suggestion({
    required this.type,
    required this.symbol,
    required this.action,
    required this.reasoning,
    required this.amount,
    this.shares = 0,
  });
}

class AllocationTarget {
  final String symbol;
  final String name;
  final double weight;
  final StockSignal signal;
  const AllocationTarget({
    required this.symbol,
    required this.name,
    required this.weight,
    required this.signal,
  });
}

class PortfolioHealth {
  final int score;
  final double annualVol;
  final double effectivePositions;
  final double cashWeight;
  final List<String> strengths;
  final List<String> weaknesses;
  const PortfolioHealth({
    required this.score,
    required this.annualVol,
    required this.effectivePositions,
    required this.cashWeight,
    required this.strengths,
    required this.weaknesses,
  });
}

class AdvisorReport {
  final RiskProfile profile;
  final PortfolioHealth health;
  final List<AllocationTarget> targets;
  final List<Suggestion> suggestions;
  final String overview;
  final double totalValue;
  final DateTime signalsDate;
  final Map<String, dynamic> modelMetrics;
  const AdvisorReport({
    required this.profile,
    required this.health,
    required this.targets,
    required this.suggestions,
    required this.overview,
    required this.totalValue,
    required this.signalsDate,
    required this.modelMetrics,
  });
}

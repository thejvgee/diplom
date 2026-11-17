import 'dart:math' as math;

import 'risk_profile.dart';
import 'signals.dart';

/// Gemini-гүй, утсан дээр ажилладаг хөрөнгө оруулалтын зөвлөх.
///
/// 1. Багцын эрүүл мэнд: төрөлжилт, эрсдэл, бэлэн мөнгө, дохио, хөрвөх
///    чадвар, салбарын төвлөрөл.
/// 2. Хуваарилалт: mean-variance оновчлол (корреляцийг shrinkage-аар
///    тогтворжуулсан), нэг хувьцааны дээд жин, хөрвөх чадварын хязгаар
///    (өдрийн дундаж арилжаагаар), салбарын дээд хязгаар.
/// 3. Зөвлөгөө: одоогийн багцыг зорилтот хуваарилалттай харьцуулж, шимтгэлийг
///    тооцоод, хэт жижиг гүйлгээ санал болгохгүй.
class AdvisorEngine {
  final SignalSet signals;

  /// Дохио хэт хуучирсан бол (жишээ нь удаан арилжаагүй) ашиглахгүй.
  static const int maxSignalAgeDays = 45;

  /// Үүнээс бага зөрүүтэй бол "барих" гэж үзнэ (нийт хөрөнгийн хувиар).
  static const double rebalanceThreshold = 0.02;

  /// Үүнээс бага дүнтэй гүйлгээ санал болгохгүй (шимтгэлд идэгдэнэ).
  static const double minTradeValue = 100000;

  /// Нэг хувьцаанд өдрийн дундаж арилжааны дүнгээс их мөнгө оруулахгүй
  /// (хэрэгтэй үед хэдхэн өдөрт зарах боломжтой байх).
  static const double liquidityDays = 1.0;

  /// "Бусад"-аас бусад нэг салбарт нийт хөрөнгийн дээд хувь.
  static const double maxSectorWeight = 0.40;

  /// Корреляцийн shrinkage: ρ' = (1−δ)·ρ + δ·ρ̄ (жижиг түүвэрт тогтвортой).
  static const double corrShrinkage = 0.3;

  static const String disclaimer =
      'Энэ нь түүхэн өгөгдөлд суурилсан автомат шинжилгээ бөгөөд санхүүгийн '
      'мэргэжлийн зөвлөгөө биш. Хөрөнгө оруулалт эрсдэлтэй тул шийдвэрээ '
      'өөрөө гаргана уу.';

  AdvisorEngine(this.signals) : _baseRate = _computeBaseRate(signals);

  final double _baseRate;

  /// Загварын зорилт "зах зээлийн дунджаас илүү өсөх" эсэх (шинэ загвар).
  bool get isRelative => signals.modelMetrics['target'] == 'excess';

  /// Магадлалын нэр (UI-д).
  String get probLabel =>
      isRelative ? 'зах зээлээс илүү өсөх магадлал' : 'өсөх магадлал';

  /// "Дундаж" магадлал — үүнтэй харьцуулж "дунджаас сайн/муу" гэж дүгнэнэ.
  /// Харьцангуй загварт: бодитоор арилжаалагддаг хувьцаануудын медиан
  /// (хэрэглэгч зөвхөн тэднийг авч чадна). Бусад үед сургалтын суурь давтамж.
  double get baseRate => _baseRate;

  static double _computeBaseRate(SignalSet signals) {
    final trained =
        (signals.modelMetrics['baseRateUp'] as num?)?.toDouble() ?? 0.5;
    if (signals.modelMetrics['target'] != 'excess') return trained;
    final tradable = [
      for (final s in signals.signals)
        if (s.liquidity >= 0.6 && s.avgTurnover >= 1e6) s.probUp
    ]..sort();
    if (tradable.length < 5) return trained;
    final mid = tradable.length ~/ 2;
    return tradable.length.isOdd
        ? tradable[mid]
        : (tradable[mid - 1] + tradable[mid]) / 2;
  }

  /// Нэг талын гүйлгээний зардал (шимтгэл + үнийн зөрүү).
  double get feePerSide =>
      (signals.modelMetrics['feePerSide'] as num?)?.toDouble() ?? 0.005;

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
    final targets = _allocate(profile, total);
    final targetW = {for (final t in targets) t.symbol: t.weight};
    final minTrade = math.max(minTradeValue, rebalanceThreshold * total);

    // --- Зөвлөгөө -----------------------------------------------------------
    final suggestions = <Suggestion>[];
    final symbols = {...currentW.keys, ...targetW.keys};
    for (final symbol in symbols) {
      final cur = currentW[symbol] ?? 0;
      final tgt = targetW[symbol] ?? 0;
      final diff = tgt - cur;
      final price = priceOf(symbol);
      final sig = signals.signalFor(symbol);
      final reason = _explain(sig);
      final target = targets.where((t) => t.symbol == symbol).firstOrNull;
      final limitNote = target?.limitedBy == null ? '' : ' ${target!.limitedBy}';

      if (cur > 0 && tgt == 0) {
        final qty = quantities[symbol] ?? 0;
        final weak = sig == null || edgeOf(sig) < -0.03;
        final why = _exclusionReason(sig, profile, total);
        if (weak || why != null) {
          final amount = cur * total;
          suggestions.add(Suggestion(
            type: SuggestionType.sell,
            symbol: symbol,
            action: '$symbol — зарах (${_fmtQty(qty)} ширхэг)',
            reasoning: [
              if (why != null) why,
              reason,
              _feeNote(amount),
            ].join(' '),
            amount: amount,
            shares: qty,
            fee: amount * feePerSide,
          ));
        } else {
          suggestions.add(Suggestion(
            type: SuggestionType.hold,
            symbol: symbol,
            action: '$symbol — барих',
            reasoning: 'Дохио төвийг сахисан тул шинээр нэмэхгүй ч яаралтай '
                'зарах шаардлагагүй (зарахад шимтгэл гарна). $reason',
            amount: 0,
          ));
        }
      } else if (diff > 0 && diff * total >= minTrade && price > 0) {
        final shares = (diff * total / price).floorToDouble();
        if (shares < 1) continue;
        final amount = shares * price;
        suggestions.add(Suggestion(
          type: SuggestionType.buy,
          symbol: symbol,
          action: '$symbol — ${_fmtQty(shares)} ширхэг авах (~${_fmtMoney(amount)}₮)',
          reasoning: 'Зорилтот жин ${_pct(tgt)} (одоо ${_pct(cur)}).$limitNote '
              '$reason ${_feeNote(amount)}',
          amount: amount,
          shares: shares,
          fee: amount * feePerSide,
        ));
      } else if (diff < 0 && -diff * total >= minTrade && price > 0) {
        final shares = math.min(
            (-diff * total / price).floorToDouble(), quantities[symbol] ?? 0);
        if (shares < 1) continue;
        final amount = shares * price;
        suggestions.add(Suggestion(
          type: SuggestionType.sell,
          symbol: symbol,
          action: '$symbol — ${_fmtQty(shares)} ширхэг зарж бууруулах',
          reasoning: 'Жин ${_pct(cur)}, ${profile.label} профайлд ${_pct(tgt)} '
              'зохимжтой.$limitNote $reason ${_feeNote(amount)}',
          amount: amount,
          shares: shares,
          fee: amount * feePerSide,
        ));
      } else if (cur > 0) {
        suggestions.add(Suggestion(
          type: SuggestionType.hold,
          symbol: symbol,
          action: '$symbol — барих',
          reasoning: 'Жин нь зорилтот түвшинд ойр (${_pct(cur)}) — жижиг '
              'тохируулга хийвэл шимтгэлд идэгдэнэ. $reason',
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
            '${targetCashW > profile.targetCash + 0.05 ? 'Хөрвөх чадвартай, сайн дохиотой хувьцаа хангалтгүй тул зорилтот бэлэн мөнгө профайлынхаас их байна. ' : ''}'
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
    final totalFees = suggestions.fold<double>(0, (a, s) => a + s.fee);

    final overview = StringBuffer()
      ..write('Таны багцын нийт үнэлгээ ${_fmtMoney(total)}₮, үүнээс '
          '${_pct(cashW)} нь бэлэн мөнгө. ')
      ..write('Багцын эрүүл мэндийн оноо ${health.score}/100. ')
      ..write(targets.isEmpty
          ? 'Одоогоор ${profile.label} профайлын шалгуурыг хангасан, дунджаас '
              'сайн дохиотой хувьцаа олдсонгүй тул бэлэн мөнгөө хадгалахыг зөвлөж байна.'
          : '${profile.label} профайлд тохируулан ${targets.length} хувьцаанд '
              'нийт хөрөнгийн ${_pct(1 - targetCashW)}-ийг хуваарилахыг санал '
              'болгож байна.')
      ..write(totalFees > 0
          ? ' Санал болгосон гүйлгээний нийт шимтгэл ~${_fmtMoney(totalFees)}₮.'
          : '');

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
    var divScore = stockW < 0.1 ? 15.0 : 30 * math.min(1.0, (effN - 1) / 5);
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

    // Салбарын төвлөрөл
    final sectors = <String, double>{};
    for (final e in w.entries) {
      final sector = signals.signalFor(e.key)?.sector ?? 'Бусад';
      sectors[sector] = (sectors[sector] ?? 0) + e.value;
    }
    final named = sectors.entries.where((e) => e.key != 'Бусад').toList();
    if (named.isNotEmpty && stockW >= 0.2) {
      final big = named.reduce((a, b) => a.value > b.value ? a : b);
      if (big.value / stockW > 0.6) {
        divScore *= 0.7;
        weaknesses.add('Салбарын төвлөрөл: хувьцааны хэсгийн '
            '${_pct(big.value / stockW)} нь "${big.key}" салбарт байна.');
      }
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

    // Дохио (жигнэсэн дундаж магадлал)
    var probSum = 0.0, liqSum = 0.0, known = 0.0;
    final weak = <String>[];
    final slowToSell = <String>[];
    for (final e in w.entries) {
      final s = signals.signalFor(e.key);
      if (s == null) continue;
      probSum += s.probUp * e.value;
      liqSum += s.liquidity * e.value;
      known += e.value;
      if (edgeOf(s) < -0.03) weak.add(e.key);
      if (s.avgTurnover > 0 && e.value * total > 5 * s.avgTurnover) {
        slowToSell.add('${e.key} (~${(e.value * total / s.avgTurnover).round()} өдөр)');
      }
    }
    final avgProb = known > 0 ? probSum / known : 0.5;
    final avgLiq = known > 0 ? liqSum / known : 1.0;
    final avgEdge = avgProb - baseRate;
    final sigScore = 15 * ((avgEdge + 0.05) / 0.1).clamp(0.0, 1.0);
    if (avgEdge >= 0.02) {
      strengths.add('Багцын хувьцаануудын дундаж $probLabel ${_pct(avgProb)} '
          'нь дунджаас (${_pct(baseRate)}) өндөр.');
    }
    if (weak.isNotEmpty) {
      weaknesses.add('Сул дохиотой хувьцаа: ${weak.join(', ')}.');
    }

    // Хөрвөх чадвар
    var liqScore = 10 * (avgLiq / profile.minLiquidity).clamp(0.0, 1.0);
    if (avgLiq < profile.minLiquidity) {
      weaknesses.add('Зарим хувьцаа ховор арилжаалагддаг тул хэрэгтэй үедээ '
          'зарахад хэцүү байж болно.');
    }
    if (slowToSell.isNotEmpty) {
      liqScore *= 0.5;
      weaknesses.add('Позиц нь өдрийн дундаж арилжаанаас хэт их тул зарахад '
          'удаан: ${slowToSell.join(', ')}.');
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

  /// Эрсдэлээс зайлсхийх коэффициент (mean-variance-д).
  static double riskAversion(RiskProfile p) =>
      2.0 + 10.0 * (p.volPenalty - 0.4) / 1.6;

  List<AllocationTarget> _allocate(RiskProfile profile, double total) {
    final newest = signals.signals.isEmpty
        ? DateTime.now()
        : signals.signals.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);

    final candidates = signals.signals
        .where((s) =>
            _exclusionReason(s, profile, total) == null &&
            newest.difference(s.date).inDays <= maxSignalAgeDays)
        .toList();
    double score(StockSignal s) =>
        edgeOf(s) / math.pow(math.max(s.annualVol, 0.05), profile.volPenalty);
    candidates.sort((a, b) => score(b).compareTo(score(a)));

    // Шунахай урьдчилсан сонголт: өндөр корреляцитай хувьцааг давхардуулахгүй
    final picked = <StockSignal>[];
    for (final c in candidates) {
      if (picked.length >= profile.maxPositions) break;
      final tooSimilar =
          picked.any((p) => signals.correlationOf(p.symbol, c.symbol) > 0.8);
      if (!tooSimilar) picked.add(c);
    }
    if (picked.isEmpty) return [];

    // Хувьцаа бүрийн дээд жин: профайл ба хөрвөх чадвар
    final caps = <String, double>{};
    final limits = <String, String?>{};
    for (final p in picked) {
      var cap = profile.maxWeight;
      String? why;
      if (p.avgTurnover > 0 && total > 0) {
        final liqCap = p.avgTurnover * liquidityDays / total;
        if (liqCap < cap) {
          cap = liqCap;
          why = 'Өдрийн дундаж арилжаа ~${_fmtMoney(p.avgTurnover)}₮ тул '
              'жинг ${_pct(cap)}-аар хязгаарласан.';
        }
      }
      caps[p.symbol] = cap;
      limits[p.symbol] = why;
    }

    final budget = 1 - profile.targetCash;
    var weights = optimizeWeights(
      picked: picked,
      caps: caps,
      budget: budget,
      riskAversion: riskAversion(profile),
    );

    // Салбарын дээд хязгаар ("Бусад"-аас бусад)
    for (var iter = 0; iter < 3; iter++) {
      final sectors = <String, double>{};
      for (final p in picked) {
        sectors[p.sector] = (sectors[p.sector] ?? 0) + (weights[p.symbol] ?? 0);
      }
      final over = sectors.entries
          .where((e) => e.key != 'Бусад' && e.value > maxSectorWeight + 1e-9)
          .toList();
      if (over.isEmpty) break;
      for (final e in over) {
        final scale = maxSectorWeight / e.value;
        for (final p in picked.where((p) => p.sector == e.key)) {
          caps[p.symbol] = (weights[p.symbol] ?? 0) * scale;
          limits[p.symbol] ??= '"${e.key}" салбарт ${_pct(maxSectorWeight)}-аас '
              'ихгүй байхаар хязгаарласан.';
        }
      }
      weights = optimizeWeights(
        picked: picked,
        caps: caps,
        budget: budget,
        riskAversion: riskAversion(profile),
      );
    }

    // Хэт жижиг (гүйлгээ хийх утгагүй) жинг хасна
    final minWeight = total > 0
        ? math.max(rebalanceThreshold, minTradeValue / total)
        : rebalanceThreshold;
    return [
      for (final p in picked)
        if ((weights[p.symbol] ?? 0) >= minWeight)
          AllocationTarget(
            symbol: p.symbol,
            name: p.name,
            weight: weights[p.symbol]!,
            signal: p,
            limitedBy: (weights[p.symbol]! >= caps[p.symbol]! - 1e-6)
                ? limits[p.symbol]
                : null,
          ),
    ]..sort((a, b) => b.weight.compareTo(a.weight));
  }

  /// Mean-variance: max μᵀw − (γ/2)·wᵀΣw, нөхцөл 0 ≤ wᵢ ≤ capᵢ, Σw = budget
  /// (боломжгүй бол Σcap). μ = дунджаас илүү магадлал, Σ = σᵢσⱼρ' (shrinkage).
  /// Проекцлосон градиентийн аргаар шийднэ.
  Map<String, double> optimizeWeights({
    required List<StockSignal> picked,
    required Map<String, double> caps,
    required double budget,
    required double riskAversion,
  }) {
    final n = picked.length;
    if (n == 0) return {};
    final mu = [for (final p in picked) edgeOf(p)];
    final sig = [for (final p in picked) math.max(p.annualVol, 0.05)];
    final cap = [for (final p in picked) math.max(0.0, caps[p.symbol] ?? 0)];

    var avgCorr = 0.0, pairs = 0;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        avgCorr += signals.correlationOf(picked[i].symbol, picked[j].symbol);
        pairs++;
      }
    }
    avgCorr = pairs == 0 ? 0 : avgCorr / pairs;
    final cov = List.generate(n, (i) => List.generate(n, (j) {
          if (i == j) return sig[i] * sig[i];
          final rho = (1 - corrShrinkage) *
                  signals.correlationOf(picked[i].symbol, picked[j].symbol) +
              corrShrinkage * avgCorr;
          return sig[i] * sig[j] * rho;
        }));

    final target = math.min(budget, cap.fold<double>(0, (a, b) => a + b));
    var w = _projectCappedSimplex(List<double>.filled(n, target / n), cap, target);
    final maxDiag = sig.map((s) => s * s).reduce(math.max);
    final lr = 1 / (riskAversion * maxDiag * n + 1e-9);
    for (var iter = 0; iter < 400; iter++) {
      final grad = List<double>.generate(n, (i) {
        var cw = 0.0;
        for (var j = 0; j < n; j++) {
          cw += cov[i][j] * w[j];
        }
        return mu[i] - riskAversion * cw;
      });
      final next = _projectCappedSimplex(
          [for (var i = 0; i < n; i++) w[i] + lr * grad[i]], cap, target);
      var delta = 0.0;
      for (var i = 0; i < n; i++) {
        delta = math.max(delta, (next[i] - w[i]).abs());
      }
      w = next;
      if (delta < 1e-7) break;
    }
    return {for (var i = 0; i < n; i++) picked[i].symbol: w[i]};
  }

  /// {0 ≤ wᵢ ≤ capᵢ, Σw = total} олонлог руу проекц (τ-г хоёртын хайлтаар).
  static List<double> _projectCappedSimplex(
      List<double> v, List<double> cap, double total) {
    double sumAt(double tau) {
      var s = 0.0;
      for (var i = 0; i < v.length; i++) {
        s += (v[i] - tau).clamp(0.0, cap[i]);
      }
      return s;
    }

    var lo = v.reduce(math.min) - cap.fold<double>(0, math.max) - 1;
    var hi = v.reduce(math.max) + 1;
    for (var k = 0; k < 80; k++) {
      final mid = (lo + hi) / 2;
      if (sumAt(mid) > total) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final tau = (lo + hi) / 2;
    return [for (var i = 0; i < v.length; i++) (v[i] - tau).clamp(0.0, cap[i])];
  }

  /// Хувьцааг профайлд оруулахгүй шалтгаан (null = тэнцэнэ).
  String? _exclusionReason(StockSignal? s, RiskProfile profile, double total) {
    if (s == null) return 'Энэ хувьцааны хангалттай арилжааны түүх алга.';
    if (s.liquidity < profile.minLiquidity) {
      return 'Ховор арилжаалагддаг (хөрвөх чадвар ${_pct(s.liquidity)}).';
    }
    if (s.avgTurnover > 0 && total > 0) {
      final maxPos = s.avgTurnover * liquidityDays;
      if (maxPos < math.max(minTradeValue, rebalanceThreshold * total)) {
        return 'Өдрийн дундаж арилжаа ~${_fmtMoney(s.avgTurnover)}₮ — '
            'таны багцын хэмжээнд хэт бага.';
      }
    }
    if (s.annualVol > profile.maxAnnualVol) {
      return 'Хэлбэлзэл ${_pct(s.annualVol)} нь ${profile.label} профайлд хэт өндөр.';
    }
    // Харьцангуй загвар хувьцааг эрэмбэлдэг тул шаардлага хангасан хувьцаанаас
    // шилдгийг нь сонгоно; зөвхөн тодорхой сул дохиотойг хасна.
    if (edgeOf(s) <= (isRelative ? -0.02 : 0.01)) {
      return 'Дохио сул: $probLabel дунджаас доогуур.';
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
      case 'relStrength20':
        return '20 өдөрт зах зээлээс ${signed(v)}';
      case 'relStrength60':
        return '60 өдөрт зах зээлээс ${signed(v)}';
      case 'logTurnover':
        return 'өдрийн арилжаа ~${_fmtMoney(math.pow(10, v) - 1)}₮';
      case 'earningsYield':
        return v > 0.0001
            ? 'P/E ≈ ${(1 / v).toStringAsFixed(1)}'
            : v < -0.0001
                ? 'алдагдалтай (EPS < 0)'
                : 'ашгийн мэдээлэлгүй';
      case 'bookToPrice':
        final bp = math.exp(v) - 1;
        return bp > 0.0001
            ? 'P/B ≈ ${(1 / bp).toStringAsFixed(2)}'
            : 'дансны үнийн мэдээлэлгүй';
      case 'roe':
        return 'ROE ${_pct(v)}';
      case 'hasFundamentals':
        return v > 0.5 ? 'санхүүгийн тайлантай' : 'санхүүгийн тайлангүй';
    }
    return name;
  }

  /// Дохиог монгол хэлээр тайлбарлана (бодит тоотой).
  String explainSignal(StockSignal? s) => _explain(s);

  String _explain(StockSignal? s) {
    if (s == null) return '';
    final drivers = s.drivers.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final top = drivers.take(2).map((e) {
      final value = s.features[e.key];
      final what = value == null ? e.key : describeFeature(e.key, value);
      return '$what (магадлалыг ${e.value >= 0 ? '↑ өсгөсөн' : '↓ бууруулсан'})';
    }).join('; ');
    final edge = edgeOf(s);
    return 'Загварын тооцоолсноор 30 хоногт $probLabel ${_pct(s.probUp)} '
        '(дунджаас ${edge >= 0 ? '+' : ''}${(edge * 100).toStringAsFixed(1)} пункт); '
        'сүүлийн 60 өдөрт ${s.ret60 >= 0 ? '+' : ''}${_pct(s.ret60)}, '
        'жилийн хэлбэлзэл ${_pct(s.annualVol)}.'
        '${top.isEmpty ? '' : ' Гол хүчин зүйл: $top.'}';
  }

  String _feeNote(double amount) =>
      'Шимтгэл ~${_fmtMoney(amount * feePerSide)}₮.';

  static String _pct(num v) => '${(v * 100).toStringAsFixed(v.abs() < 0.1 ? 1 : 0)}%';
  static String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
  static String _fmtMoney(num v) {
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

  /// Тооцоолсон гүйлгээний зардал (₮).
  final double fee;
  const Suggestion({
    required this.type,
    required this.symbol,
    required this.action,
    required this.reasoning,
    required this.amount,
    this.shares = 0,
    this.fee = 0,
  });
}

class AllocationTarget {
  final String symbol;
  final String name;
  final double weight;
  final StockSignal signal;

  /// Жинг юугаар хязгаарласан (хөрвөх чадвар, салбар) — тайлбарт.
  final String? limitedBy;
  const AllocationTarget({
    required this.symbol,
    required this.name,
    required this.weight,
    required this.signal,
    this.limitedBy,
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

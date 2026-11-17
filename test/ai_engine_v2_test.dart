import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/ai_engine/advisor_engine.dart';
import 'package:jvgee_diplom/ai_engine/chat_tools.dart';
import 'package:jvgee_diplom/ai_engine/features.dart';
import 'package:jvgee_diplom/ai_engine/fundamentals.dart';
import 'package:jvgee_diplom/ai_engine/gbm.dart';
import 'package:jvgee_diplom/ai_engine/goal_planner.dart';
import 'package:jvgee_diplom/ai_engine/logistic_model.dart';
import 'package:jvgee_diplom/ai_engine/risk_profile.dart';
import 'package:jvgee_diplom/ai_engine/signals.dart';
import 'package:jvgee_diplom/models/mse_quote.dart';

StockSignal _sig(String s, double p, double vol,
        {double liq = 1, double turnover = 0, String sector = 'Бусад'}) =>
    StockSignal(
      symbol: s,
      name: '$s ХК',
      category: 1,
      date: DateTime(2026, 11, 16),
      price: 1000,
      probUp: p,
      dailyVol: vol / math.sqrt(250),
      ret20: 0,
      ret60: 0,
      drawdown60: 0,
      liquidity: liq,
      rsi: 50,
      avgTurnover: turnover,
      sector: sector,
      drivers: {'ret20': 0.1},
      features: {'ret20': 0.02},
    );

void main() {
  group('Шинж ба өгөгдөл', () {
    test('MarketIndex: тэнцүү жинтэй индексийн өгөөж', () {
      List<MseDailyBar> bars(double step) => [
            for (var i = 0; i < 10; i++)
              MseDailyBar(
                date: DateTime(2025, 1, 1 + i),
                open: 100,
                high: 100,
                low: 100,
                close: 100 * math.pow(1 + step, i).toDouble(),
                volume: 1,
              )
          ];
      final idx = MarketIndex.fromHistories([bars(0.01), bars(0.01), bars(0.01)]);
      // Индекс эхний өгөөжийн өдрөөс (1-р сарын 2) эхэлнэ
      expect(idx.returnBetween(DateTime(2024, 12, 1), DateTime(2025, 1, 10)), isNull);
      final r = idx.returnBetween(DateTime(2025, 1, 2), DateTime(2025, 1, 10))!;
      expect(r, closeTo(math.pow(1.01, 8) - 1, 1e-9));
    });

    test('санхүүгийн тайланг нийтлэгдсэн огнооноос хойш л ашиглана', () {
      final f = FundamentalsSeries([
        FinancialReport(
            year: 2023, season: 4, published: DateTime(2024, 2, 27),
            eps: 145, bvps: 600, roe: 24),
        FinancialReport(
            year: 2024, season: 2, published: DateTime(2024, 7, 19),
            eps: 80, bvps: 650, roe: 12),
      ]);
      expect(f.at(DateTime(2024, 1, 1)).isEmpty, isTrue);
      final s = f.at(DateTime(2024, 8, 1));
      expect(s.eps, 145); // жилийн тайлангийн EPS (хагас жилийнхийг биш)
      expect(s.bvps, 650); // хамгийн сүүлийн тайлангийн BVPS
      expect(s.roe, closeTo(0.24, 1e-9));
    });

    test('нэрээр салбар таамаглах', () {
      expect(SectorGuess.of('Хаан банк ХК'), 'Санхүү');
      expect(SectorGuess.of('Таван толгой ХК'), 'Уул уурхай, эрчим хүч');
      expect(SectorGuess.of('Сүү ХК'), 'Хүнс, хэрэглээ');
    });

    test('forwardReturn: дараагийн өдөр авах (entryLag)', () {
      final bars = [
        for (var i = 0; i < 40; i++)
          MseDailyBar(
              date: DateTime(2025, 1, 1).add(Duration(days: i)),
              open: 100.0 + i,
              high: 100.0 + i,
              low: 100.0 + i,
              close: 100.0 + i,
              volume: 1)
      ];
      final r0 = FeatureExtractor.forwardReturn(bars, 0, horizonDays: 30)!;
      final r1 = FeatureExtractor.forwardReturn(bars, 0, horizonDays: 30, entryLag: 1)!;
      expect(r0, closeTo(130 / 100 - 1, 1e-9));
      expect(r1, closeTo(131 / 101 - 1, 1e-9));
    });
  });

  group('Загварууд', () {
    final rnd = math.Random(3);
    final xs = <List<double>>[], ys = <int>[];
    for (var i = 0; i < 3000; i++) {
      final a = rnd.nextDouble() * 2 - 1, b = rnd.nextDouble() * 2 - 1;
      xs.add([a, b]);
      // шугаман бус хамаарал: |a| их бол 1
      ys.add(a.abs() > 0.5 ? 1 : 0);
    }

    test('GBM шугаман бус хамаарлыг сурч, нөлөөний нийлбэр = margin', () {
      final gbm = GbmModel.train(xs, ys, featureNames: ['a', 'b'], minLeaf: 50, nTrees: 80, learningRate: 0.2);
      final auc = rocAuc([for (final x in xs) gbm.margin(x)], ys);
      expect(auc, greaterThan(0.95));
      final logit = LogisticModel.train(xs, ys, featureNames: ['a', 'b']);
      expect(rocAuc([for (final x in xs) logit.margin(x)], ys), lessThan(0.7));

      final x = [0.8, 0.1];
      final c = gbm.contributions(x);
      var rootSum = gbm.baseMargin;
      for (final t in gbm.trees) {
        rootSum += t[0][4];
      }
      expect(rootSum + c.values.reduce((p, q) => p + q), closeTo(gbm.margin(x), 1e-9));
      expect(GbmModel.fromJson(gbm.toJson()).margin(x), closeTo(gbm.margin(x), 1e-5));
    });

    test('Ньютоны логистик регресс нийлнэ', () {
      final lin = [for (final x in xs) x[0] > 0 ? 1 : 0];
      final m = LogisticModel.train(xs, lin, featureNames: ['a', 'b']);
      expect(m.predict([0.9, 0]), greaterThan(0.9));
      expect(m.predict([-0.9, 0]), lessThan(0.1));
    });

    test('Platt тохируулга хэт итгэлтэй таамгийг засна', () {
      // жинхэнэ магадлал σ(z/2), загвар z гэж хэт итгэлтэй таамагласан
      final margins = <double>[], labels = <int>[];
      for (var i = 0; i < 4000; i++) {
        final z = rnd.nextDouble() * 6 - 3;
        margins.add(z);
        labels.add(rnd.nextDouble() < sigmoid(z / 2) ? 1 : 0);
      }
      final cal = PlattCalibration.fit(margins, labels);
      expect(cal.a, closeTo(0.5, 0.1));
      expect(cal.b, closeTo(0, 0.1));
    });

    test('Spearman', () {
      expect(spearman([1, 2, 3, 4], [10, 20, 30, 40]), closeTo(1, 1e-9));
      expect(spearman([1, 2, 3, 4], [4, 3, 2, 1]), closeTo(-1, 1e-9));
    });
  });

  group('Оновчлол', () {
    final set = SignalSet(
      generatedAt: DateTime(2026, 11, 18),
      modelMetrics: {'target': 'excess', 'baseRateUp': 0.44, 'feePerSide': 0.005},
      signals: [
        _sig('A', 0.50, 0.25, turnover: 5e7, sector: 'Санхүү'),
        _sig('B', 0.49, 0.30, turnover: 5e7, sector: 'Санхүү'),
        _sig('C', 0.48, 0.20, turnover: 5e7, sector: 'Санхүү'),
        _sig('D', 0.47, 0.35, turnover: 4e5),
        _sig('E', 0.46, 0.30, turnover: 5e7),
        _sig('F', 0.40, 0.30, turnover: 5e7),
        _sig('ILLQ', 0.60, 0.30, turnover: 5e3),
      ],
    );
    final engine = AdvisorEngine(set);

    test('суурь нь арилжаалагддаг хувьцааны медиан', () {
      // turnover ≥ 1e6: A,B,C,E,F → медиан 0.48
      expect(engine.baseRate, closeTo(0.48, 1e-9));
    });

    test('төсвийг бүрэн хуваарилж, хязгааруудыг сахина', () {
      final profile = RiskProfile.fromKey('Aggressive');
      final r = engine.analyze(holdings: [], cash: 1e7, profile: profile);
      final w = {for (final t in r.targets) t.symbol: t.weight};
      expect(w.containsKey('ILLQ'), isFalse); // хэт бага арилжаа
      expect(w.containsKey('F'), isFalse); // сул дохио
      for (final v in w.values) {
        expect(v, lessThanOrEqualTo(profile.maxWeight + 1e-6));
      }
      // D: өдрийн арилжаа 400k → 10 саяын багцад ≤ 4%
      if (w.containsKey('D')) expect(w['D']!, lessThanOrEqualTo(0.04 + 1e-6));
      // Санхүүгийн салбар ≤ 40%
      final fin = (w['A'] ?? 0) + (w['B'] ?? 0) + (w['C'] ?? 0);
      expect(fin, lessThanOrEqualTo(AdvisorEngine.maxSectorWeight + 1e-6));
      // шимтгэл тооцогдсон
      expect(r.suggestions.where((s) => s.type == SuggestionType.buy).every((s) => s.fee > 0), isTrue);
    });

    test('жижиг зөрүүтэй бол гүйлгээ санал болгохгүй', () {
      final profile = RiskProfile.fromKey('Aggressive');
      final first = engine.analyze(holdings: [], cash: 1e7, profile: profile);
      final holdings = [
        for (final s in first.suggestions.where((s) => s.type == SuggestionType.buy))
          HoldingInput(symbol: s.symbol, quantity: s.shares, averageCost: 1000, currentPrice: 1000)
      ];
      final spent = first.suggestions
          .where((s) => s.type == SuggestionType.buy)
          .fold<double>(0, (a, s) => a + s.amount);
      final again = engine.analyze(holdings: holdings, cash: 1e7 - spent, profile: profile);
      expect(again.suggestions.where((s) => s.type == SuggestionType.buy || s.type == SuggestionType.sell), isEmpty);
    });
  });

  group('Зорилгын төлөвлөгч v2', () {
    test('инфляци нь бодит үнэ цэнийг бууруулна', () {
      const base = MarketAssumptions(stockMonthlyMean: 0, stockMonthlyVol: 1e-9, cashAnnualRate: 0.1);
      const infl = MarketAssumptions(
          stockMonthlyMean: 0, stockMonthlyVol: 1e-9, cashAnnualRate: 0.1, inflationAnnual: 0.1);
      double median(MarketAssumptions a) => GoalPlanner(a, paths: 20)
          .plan(target: 1, years: 1, initial: 1e6, stockShare: 0)
          .bands(0, percentiles: [0.5])
          .first
          .last;
      expect(median(base), closeTo(1.1e6, 10));
      expect(median(infl), closeTo(1e6, 10)); // 10% хүү − 10% инфляци = 0
    });

    test('bootstrap ба glide path', () {
      final series = [for (var i = 0; i < 60; i++) i.isEven ? 0.03 : -0.01];
      final a = MarketAssumptions.fromMetrics(
          {'monthlyMean': 0.01, 'monthlyVol': 0.02, 'monthlySeries': series, 'since': '2021-01', 'months': 60});
      expect(a.usesBootstrap, isTrue);
      final plan = GoalPlanner(a).plan(
          target: 2e7, years: 5, initial: 5e6, stockShare: 0.8, glidePath: true);
      expect(plan.finalStockShare, closeTo(0.4, 1e-9));
      expect(GoalPlanner.stockShareAt(0, 60, 0.8, true), 0.8);
      expect(plan.worstTenPercent(200000), lessThan(plan.bands(200000).last.last));
    });
  });

  group('Чатын функцууд', () {
    final set = SignalSet(
      generatedAt: DateTime(2026, 11, 18),
      modelMetrics: {'target': 'excess', 'baseRateUp': 0.44, 'testAuc': 0.55},
      signals: [
        for (var i = 0; i < 6; i++) _sig('S$i', 0.42 + i * 0.01, 0.3, turnover: 5e7),
      ],
    );
    final ctx = ChatToolContext(
      signals: set,
      holdings: [HoldingInput(symbol: 'S0', quantity: 100, averageCost: 900)],
      cash: 5e6,
      profile: RiskProfile.fromKey('Moderate'),
    );

    test('бүх функц бодит өгөгдлөөр хариулна', () {
      expect(ChatTools.execute('analyze_portfolio', {}, ctx)['healthScore'], isA<int>());
      expect(ChatTools.execute('get_stock_signal', {'symbol': 's5'}, ctx)['symbol'], 'S5');
      expect(ChatTools.execute('get_stock_signal', {'symbol': 'XXX'}, ctx)['error'], isNotNull);
      final top = ChatTools.execute('top_signals', {'count': 3}, ctx)['stocks'] as List;
      expect((top.first as Map)['symbol'], 'S5');
      expect(ChatTools.execute('investment_plan', {'amount': 1e7}, ctx)['allocations'], isNotEmpty);
      final goal = ChatTools.execute('goal_plan', {'target': 2e7, 'years': 3, 'monthly': 3e5}, ctx);
      expect(goal['requiredMonthly80pct'], isA<int>());
      expect(goal['probabilityWithMonthly'], isA<double>());
      expect(ChatTools.execute('model_performance', {}, ctx)['walkForwardAuc'], 0.55);
      expect(ChatTools.specs.map((s) => s.name), contains('goal_plan'));
    });
  });
}

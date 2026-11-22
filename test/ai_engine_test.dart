import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/ai_engine/advisor_engine.dart';
import 'package:jvgee_diplom/ai_engine/features.dart';
import 'package:jvgee_diplom/ai_engine/logistic_model.dart';
import 'package:jvgee_diplom/ai_engine/risk_profile.dart';
import 'package:jvgee_diplom/ai_engine/signals.dart';
import 'package:jvgee_diplom/models/mse_quote.dart';

List<MseDailyBar> _bars(List<double> closes) => [
      for (var i = 0; i < closes.length; i++)
        MseDailyBar(
          date: DateTime(2025, 1, 1).add(Duration(days: i + (i ~/ 5) * 2)),
          open: closes[i],
          close: closes[i],
          high: closes[i],
          low: closes[i],
          volume: 100,
        )
    ];

StockSignal _sig(String s, double p, double vol,
        {double liq = 1, DateTime? date}) =>
    StockSignal(
      symbol: s,
      name: '$s ХК',
      category: 1,
      date: date ?? DateTime(2026, 11, 12),
      price: 1000,
      probUp: p,
      dailyVol: vol / math.sqrt(250),
      ret20: 0.02,
      ret60: 0.05,
      drawdown60: -0.03,
      liquidity: liq,
      rsi: 55,
      drivers: {'ret60': 0.2, 'dd60': -0.1},
    );

SignalSet _set(List<StockSignal> s) => SignalSet(
      generatedAt: DateTime(2026, 11, 15),
      signals: s,
      modelMetrics: {'baseRateUp': 0.46},
    );

void main() {
  group('FeatureExtractor', () {
    test('шинжүүдийг зөв тооцоолно', () {
      final bars = _bars([for (var i = 0; i < 70; i++) 100.0 + i]);
      final x = FeatureExtractor.compute(bars, 69)!;
      expect(x.length, FeatureExtractor.names.length);
      expect(x[0], closeTo(169 / 164 - 1, 1e-9)); // ret5
      expect(x[8], 0); // дээд цэг дээрээ
      expect(x[5], 0.5); // зөвхөн өсөлт → RSI 100
      expect(x[10], greaterThan(0.9)); // өдөр бүр арилжаалагдсан
    });

    test('хангалттай түүхгүй эсвэл split-тэй бол null', () {
      final short = _bars([for (var i = 0; i < 30; i++) 100.0]);
      expect(FeatureExtractor.compute(short, 29), isNull);
      final split = _bars([for (var i = 0; i < 70; i++) i < 40 ? 1000.0 : 100.0]);
      expect(FeatureExtractor.compute(split, 69), isNull);
    });

    test('forwardReturn нь 30 хоногийн дараах өгөөж', () {
      final bars = _bars([for (var i = 0; i < 70; i++) 100.0 + i]);
      final r = FeatureExtractor.forwardReturn(bars, 0)!;
      expect(r, greaterThan(0));
      expect(FeatureExtractor.forwardReturn(bars, 69), isNull);
    });
  });

  group('LogisticModel', () {
    test('салгагдах өгөгдлийг сурч, JSON-оор хадгалагдана', () {
      final rnd = math.Random(1);
      final xs = <List<double>>[], ys = <int>[];
      for (var i = 0; i < 400; i++) {
        final a = rnd.nextDouble() * 2 - 1, b = rnd.nextDouble();
        xs.add([a, b]);
        ys.add(a > 0 ? 1 : 0);
      }
      final m = LogisticModel.train(xs, ys, featureNames: ['a', 'b']);
      expect(m.predict([0.8, 0.5]), greaterThan(0.8));
      expect(m.predict([-0.8, 0.5]), lessThan(0.2));
      final auc = rocAuc([for (final x in xs) m.predict(x)], ys);
      expect(auc, greaterThan(0.95));

      final copy = LogisticModel.fromJson(m.toJson());
      expect(copy.predict([0.3, 0.1]), closeTo(m.predict([0.3, 0.1]), 1e-12));
    });

    test('rocAuc: санамсаргүй = 0.5, төгс = 1', () {
      expect(rocAuc([0.1, 0.2, 0.8, 0.9], [0, 0, 1, 1]), 1);
      expect(rocAuc([0.5, 0.5, 0.5, 0.5], [0, 1, 0, 1]), 0.5);
    });
  });

  group('RiskQuestionnaire', () {
    test('бага оноо → консерватив, их оноо → түрэмгий', () {
      expect(RiskQuestionnaire.evaluate([0, 0, 0, 0, 0, 0]).key, 'Conservative');
      expect(RiskQuestionnaire.evaluate([3, 3, 3, 3, 3, 3]).key, 'Aggressive');
      expect(RiskQuestionnaire.evaluate([1, 2, 1, 2, 1, 2]).key, 'Moderate');
    });
  });

  group('AdvisorEngine', () {
    final signals = _set([
      _sig('AAA', 0.60, 0.25),
      _sig('BBB', 0.56, 0.30),
      _sig('CCC', 0.58, 0.90), // хэт хэлбэлзэлтэй
      _sig('DDD', 0.62, 0.20, liq: 0.2), // ховор арилжаалагддаг
      _sig('EEE', 0.38, 0.25), // сул дохио
      _sig('OLD', 0.65, 0.20, date: DateTime(2026, 6, 1)), // хуучирсан
    ]);
    final engine = AdvisorEngine(signals);

    test('профайлын шалгуураар хувьцаа сонгож, жин хязгаарлана', () {
      final profile = RiskProfile.fromKey('Conservative');
      final r = engine.analyze(holdings: [], cash: 1e7, profile: profile);
      final syms = r.targets.map((t) => t.symbol).toSet();
      expect(syms, {'AAA', 'BBB'});
      for (final t in r.targets) {
        expect(t.weight, lessThanOrEqualTo(profile.maxWeight + 1e-9));
      }
      final invested = r.targets.fold<double>(0, (a, t) => a + t.weight);
      expect(invested, lessThanOrEqualTo(1 - profile.targetCash + 1e-9));
      expect(r.suggestions.where((s) => s.type == SuggestionType.buy).length, 2);
    });

    test('түрэмгий профайл хэлбэлзэлтэй хувьцааг зөвшөөрнө', () {
      final r = engine.analyze(
          holdings: [], cash: 1e7, profile: RiskProfile.fromKey('Aggressive'));
      expect(r.targets.map((t) => t.symbol), contains('CCC'));
      expect(r.targets.map((t) => t.symbol), isNot(contains('OLD')));
    });

    test('сул дохиотой, төвлөрсөн багцад зарах санал өгнө', () {
      final r = engine.analyze(
        holdings: [
          HoldingInput(symbol: 'EEE', quantity: 5000, averageCost: 900),
          HoldingInput(symbol: 'AAA', quantity: 10, averageCost: 900),
        ],
        cash: 1e6,
        profile: RiskProfile.fromKey('Moderate'),
        livePrices: {'EEE': 1000, 'AAA': 1000},
      );
      final sell = r.suggestions.firstWhere((s) => s.symbol == 'EEE');
      expect(sell.type, SuggestionType.sell);
      expect(sell.shares, 5000);
      expect(r.health.weaknesses.join(' '), contains('EEE'));
      expect(r.health.score, inInclusiveRange(0, 100));
    });

    test('корреляци ашиглан багцын хэлбэлзэл тооцоолно', () {
      final set = SignalSet(
        generatedAt: DateTime(2026, 11, 15),
        signals: [_sig('A', 0.6, 0.3), _sig('B', 0.6, 0.3)],
        corrSymbols: ['A', 'B'],
        correlation: [
          [1, 0],
          [0, 1]
        ],
      );
      final vol = AdvisorEngine(set).portfolioVolatility({'A': 0.5, 'B': 0.5});
      expect(vol, closeTo(0.3 / math.sqrt(2), 1e-9));
    });

    test('SignalSet JSON-оор бүрэн сэргэнэ', () {
      final copy = SignalSet.fromJson(signals.toJson());
      expect(copy.signals.length, signals.signals.length);
      expect(copy.signalFor('AAA')!.probUp, 0.6);
      expect(copy.modelMetrics['baseRateUp'], 0.46);
    });
  });
}

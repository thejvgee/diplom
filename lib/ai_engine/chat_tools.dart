import 'advisor_engine.dart';
import 'goal_planner.dart';
import 'risk_profile.dart';
import 'signals.dart';

/// AI чатын (Gemini function calling) хэрэгслүүд. Gemini өөрөө тоо зохиохын
/// оронд эдгээр функцийг дуудаж, апп-ын AI engine-ээс бодит үр дүн авна.
/// SDK-аас хамааралгүй (цэвэр Dart) тул тестлэгдэнэ.
class ChatToolParam {
  final String type; // 'string' | 'number' | 'integer'
  final String description;
  final bool required;
  const ChatToolParam(this.type, this.description, {this.required = false});
}

class ChatToolSpec {
  final String name;
  final String description;
  final Map<String, ChatToolParam> params;
  const ChatToolSpec(this.name, this.description, [this.params = const {}]);
}

class ChatToolContext {
  final SignalSet? signals;
  final List<HoldingInput> holdings;
  final double cash;
  final RiskProfile profile;
  final Map<String, double> livePrices;

  const ChatToolContext({
    required this.signals,
    required this.holdings,
    required this.cash,
    required this.profile,
    this.livePrices = const {},
  });
}

class ChatTools {
  static const List<ChatToolSpec> specs = [
    ChatToolSpec(
      'analyze_portfolio',
      'Хэрэглэгчийн симуляцийн багцыг шинжилнэ: эрүүл мэндийн оноо, давуу/сул '
          'тал, зорилтот хуваарилалт, авах/зарах санал.',
    ),
    ChatToolSpec(
      'get_stock_signal',
      'MSE-ийн нэг хувьцааны AI дохио: зах зээлээс илүү өсөх магадлал, '
          'хэлбэлзэл, арилжааны дүн, шийдвэрт нөлөөлсөн хүчин зүйлс.',
      {
        'symbol': ChatToolParam('string', 'Хувьцааны тэмдэг, жишээ нь APU, KHAN',
            required: true),
      },
    ),
    ChatToolSpec(
      'top_signals',
      'Идэвхтэй арилжаалагддаг хувьцаануудаас AI дохио хамгийн сайн нь.',
      {'count': ChatToolParam('integer', 'Хэдэн хувьцаа (1-10)')},
    ),
    ChatToolSpec(
      'investment_plan',
      'Тодорхой дүнг (төгрөг) хэрэглэгчийн эрсдэлийн профайлаар хувьцаанд '
          'хуваарилах санал: хувьцаа, жин, ширхэг.',
      {
        'amount': ChatToolParam('number', 'Хөрөнгө оруулах дүн, төгрөгөөр',
            required: true),
      },
    ),
    ChatToolSpec(
      'goal_plan',
      '"N жилд X төгрөг хуримтлуулах" зорилгын Monte Carlo тооцоо: сард хэдийг '
          'хуримтлуулбал 50%/80% магадлалтай хүрэх вэ.',
      {
        'target': ChatToolParam('number', 'Зорилтот дүн (төгрөг, өнөөгийн үнээр)',
            required: true),
        'years': ChatToolParam('integer', 'Хугацаа (жил)', required: true),
        'initial': ChatToolParam(
            'number', 'Одоо байгаа мөнгө (төгрөг). Өгөөгүй бол багцын үнэлгээ'),
        'monthly': ChatToolParam(
            'number', 'Сард хуримтлуулах дүн — өгвөл хүрэх магадлалыг тооцно'),
      },
    ),
    ChatToolSpec(
      'model_performance',
      'AI загварын шалгалтын үр дүн: walk-forward AUC, backtest (шимтгэлтэй), '
          'бодит гүйцэтгэлийн бүртгэл.',
    ),
  ];

  static Map<String, Object?> execute(
    String name,
    Map<String, Object?> args,
    ChatToolContext ctx,
  ) {
    final signals = ctx.signals;
    if (signals == null) return {'error': 'AI загварын өгөгдөл ачаалагдаагүй'};
    final engine = AdvisorEngine(signals);
    switch (name) {
      case 'analyze_portfolio':
        final r = engine.analyze(
          holdings: ctx.holdings,
          cash: ctx.cash,
          profile: ctx.profile,
          livePrices: ctx.livePrices,
        );
        return {
          'profile': ctx.profile.label,
          'totalValueMnt': r.totalValue.round(),
          'healthScore': r.health.score,
          'cashWeight': _r(r.health.cashWeight),
          'annualVolatility': _r(r.health.annualVol),
          'strengths': r.health.strengths,
          'weaknesses': r.health.weaknesses,
          'targetAllocation': [
            for (final t in r.targets)
              {'symbol': t.symbol, 'name': t.name, 'weight': _r(t.weight)}
          ],
          'suggestions': [
            for (final s in r.suggestions.take(8)) {'type': s.type.name, 'action': s.action}
          ],
        };

      case 'get_stock_signal':
        final symbol = '${args['symbol'] ?? ''}'.trim().toUpperCase();
        final s = signals.signalFor(symbol);
        if (s == null) {
          return {'error': '$symbol-д AI дохио алга (III ангилал эсвэл түүх хангалтгүй)'};
        }
        final drivers = s.drivers.entries.toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
        return {
          'symbol': s.symbol,
          'name': s.name,
          'sector': s.sector,
          'dataDate': s.date.toIso8601String().substring(0, 10),
          'priceMnt': ctx.livePrices[s.symbol] ?? s.price,
          'probabilityOutperform': _r(s.probUp),
          'tradableMedianProbability': _r(engine.baseRate),
          'annualVolatility': _r(s.annualVol),
          'return60d': _r(s.ret60),
          'avgDailyTurnoverMnt': s.avgTurnover.round(),
          'keyDrivers': [
            for (final d in drivers.take(4))
              '${AdvisorEngine.describeFeature(d.key, s.features[d.key] ?? 0)} '
                  '(${d.value >= 0 ? 'өсгөсөн' : 'бууруулсан'})'
          ],
        };

      case 'top_signals':
        final n = ((args['count'] as num?)?.toInt() ?? 5).clamp(1, 10);
        final list = signals.signals
            .where((s) => s.liquidity >= 0.6 && s.avgTurnover >= 1e6)
            .toList()
          ..sort((a, b) => b.probUp.compareTo(a.probUp));
        return {
          'tradableMedianProbability': _r(engine.baseRate),
          'stocks': [
            for (final s in list.take(n))
              {
                'symbol': s.symbol,
                'name': s.name,
                'probabilityOutperform': _r(s.probUp),
                'annualVolatility': _r(s.annualVol),
                'avgDailyTurnoverMnt': s.avgTurnover.round(),
              }
          ],
        };

      case 'investment_plan':
        final amount = (args['amount'] as num?)?.toDouble() ?? 0;
        if (amount < 10000) return {'error': 'Дүн хэт бага'};
        final r = engine.analyze(
          holdings: const [],
          cash: amount,
          profile: ctx.profile,
          livePrices: ctx.livePrices,
        );
        final buys = {
          for (final s in r.suggestions.where((s) => s.type == SuggestionType.buy))
            s.symbol: s
        };
        final invested = buys.values.fold<double>(0, (a, s) => a + s.amount);
        return {
          'profile': ctx.profile.label,
          'amountMnt': amount.round(),
          'allocations': [
            for (final t in r.targets)
              {
                'symbol': t.symbol,
                'name': t.name,
                'weight': _r(t.weight),
                'shares': buys[t.symbol]?.shares.round() ?? 0,
                'costMnt': buys[t.symbol]?.amount.round() ?? 0,
              }
          ],
          'cashMnt': (amount - invested).round(),
          'estimatedFeesMnt': buys.values.fold<double>(0, (a, s) => a + s.fee).round(),
        };

      case 'goal_plan':
        final target = (args['target'] as num?)?.toDouble() ?? 0;
        final years = (args['years'] as num?)?.toInt() ?? 0;
        if (target <= 0 || years <= 0) return {'error': 'target, years шаардлагатай'};
        final market = signals.modelMetrics['market'];
        final assumptions = MarketAssumptions.fromMetrics(
          market is Map ? Map<String, dynamic>.from(market) : null,
          cashAnnualRate: 0.10,
          inflationAnnual: 0.07,
          annualFee: 0.01,
        );
        final initial = (args['initial'] as num?)?.toDouble() ??
            (ctx.cash +
                ctx.holdings.fold<double>(
                    0,
                    (a, h) =>
                        a +
                        h.quantity *
                            (ctx.livePrices[h.symbol] ??
                                (h.currentPrice > 0 ? h.currentPrice : h.averageCost))));
        final plan = GoalPlanner(assumptions).plan(
          target: target,
          years: years,
          initial: initial,
          stockShare: 1 - ctx.profile.targetCash,
          glidePath: true,
        );
        final monthly = (args['monthly'] as num?)?.toDouble();
        return {
          'targetMnt': target.round(),
          'years': plan.years,
          'initialMnt': initial.round(),
          'requiredMonthly50pct': _money(plan.requiredMonthly(0.5)),
          'requiredMonthly80pct': _money(plan.requiredMonthly(0.8)),
          if (monthly != null) 'probabilityWithMonthly': _r(plan.probability(monthly)),
          if (monthly != null) 'medianFinalMnt': plan.bands(monthly, percentiles: [0.5]).first.last.round(),
          'assumptions': 'Өнөөгийн мөнгөөр (инфляци 7%), хадгаламж 10%, зардал 1%, '
              '${ctx.profile.label} профайл, ${assumptions.source}',
        };

      case 'model_performance':
        final m = signals.modelMetrics;
        return {
          'model': m['modelType'],
          'target': m['target'] == 'excess'
              ? '30 хоногт зах зээлийн дунджаас илүү өсөх эсэх'
              : '30 хоногт өсөх эсэх',
          'walkForwardAuc': m['testAuc'],
          'rankIc': m['rankIc'],
          'backtestWithFees': m['backtest'],
          'liveTrackRecord': m['trackRecord'],
          'signalsGeneratedAt': signals.generatedAt.toIso8601String().substring(0, 10),
        };
    }
    return {'error': 'Үл мэдэгдэх функц: $name'};
  }

  static double _r(num v) => (v * 10000).roundToDouble() / 10000;
  static Object _money(double v) => v.isFinite ? v.round() : 'хүрэх боломжгүй';
}

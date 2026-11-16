// AI зөвлөхийн загварыг сургах, шалгах, апп-д зориулсан дохио гаргах.
//
//   dart run tool/build_dataset.dart   # (эхлээд) MSE-ийн түүх татах
//   dart run tool/train_advisor.dart   # сургаад assets/ai/*.json бичнэ
//
// Гаралт:
//   assets/ai/advisor_model.json  — загварын жин, стандартчлал, үзүүлэлтүүд
//   assets/ai/signals.json        — хувьцаа бүрийн өнөөдрийн дохио + корреляци
//   docs/ai_model_report.md       — дипломын тайланд зориулсан үр дүн
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:jvgee_diplom/ai_engine/features.dart';
import 'package:jvgee_diplom/ai_engine/logistic_model.dart';
import 'package:jvgee_diplom/ai_engine/signals.dart';
import 'package:jvgee_diplom/models/mse_quote.dart';

/// Энэ огнооноос өмнөх өгөгдлөөр сургаж, хойшхоор шалгана.
final testStart = DateTime(2024, 1, 1);
const horizonDays = 30;

class Sample {
  final String symbol;
  final DateTime date;
  final List<double> x;
  final double fwd;
  Sample(this.symbol, this.date, this.x, this.fwd);
  int get y => fwd > 0 ? 1 : 0;
}

Future<void> main() async {
  final securities = [
    for (final s in jsonDecode(File('tool/data/securities.json').readAsStringSync()) as List)
      s as Map<String, dynamic>
  ];
  final histories = <String, List<MseDailyBar>>{};
  final names = <String, String>{};
  final categories = <String, int>{};
  for (final s in securities) {
    final sym = s['symbol'] as String;
    final f = File('tool/data/history/$sym.json');
    if (!f.existsSync()) continue;
    names[sym] = s['name'] as String;
    categories[sym] = s['category'] as int;
    histories[sym] = [
      for (final r in jsonDecode(f.readAsStringSync()) as List)
        if (!(r[0] as String).startsWith('-') && !(r[0] as String).startsWith('0'))
        MseDailyBar(
          date: DateTime.parse(r[0] as String),
          open: (r[1] as num).toDouble(),
          high: (r[2] as num).toDouble(),
          low: (r[3] as num).toDouble(),
          close: (r[4] as num).toDouble(),
          volume: (r[5] as num).toInt(),
        )
    ];
  }
  stdout.writeln('Хувьцаа: ${histories.length}');

  // --- Датасет ---------------------------------------------------------------
  final samples = <Sample>[];
  for (final e in histories.entries) {
    final bars = e.value;
    for (var i = FeatureExtractor.lookback; i < bars.length; i++) {
      final x = FeatureExtractor.compute(bars, i);
      if (x == null) continue;
      final fwd = FeatureExtractor.forwardReturn(bars, i, horizonDays: horizonDays);
      if (fwd == null) continue;
      samples.add(Sample(e.key, bars[i].date, x, fwd));
    }
  }
  // Сургалтын шошго тестийн үе рүү "алдагдахгүй" байхаар зай (embargo) авна.
  final embargo = testStart.subtract(const Duration(days: horizonDays + 5));
  final train = samples.where((s) => s.date.isBefore(embargo)).toList();
  final test = samples.where((s) => !s.date.isBefore(testStart)).toList();
  stdout.writeln('Нийт жишээ: ${samples.length}, сургалт: ${train.length}, тест: ${test.length}');

  // --- Сургалт ба үнэлгээ ----------------------------------------------------
  final sw = Stopwatch()..start();
  final model = LogisticModel.train(
    [for (final s in train) s.x],
    [for (final s in train) s.y],
    featureNames: FeatureExtractor.names,
  );
  stdout.writeln('Сургалт: ${sw.elapsedMilliseconds}ms');

  final probs = [for (final s in test) model.predict(s.x)];
  final labels = [for (final s in test) s.y];
  final auc = rocAuc(probs, labels);
  final trainAuc = rocAuc([for (final s in train) model.predict(s.x)], [for (final s in train) s.y]);
  var correct = 0;
  for (var i = 0; i < test.length; i++) {
    if ((probs[i] > 0.5 ? 1 : 0) == labels[i]) correct++;
  }
  final accuracy = correct / test.length;
  final baseRate = labels.where((y) => y == 1).length / labels.length;
  final baseline = math.max(baseRate, 1 - baseRate);

  // Магадлалын 5 бүлэг тус бүрийн дундаж ирээдүйн өгөөж
  final order = List<int>.generate(test.length, (i) => i)
    ..sort((a, b) => probs[a].compareTo(probs[b]));
  final quintiles = <Map<String, double>>[];
  for (var q = 0; q < 5; q++) {
    final part = order.sublist(q * order.length ~/ 5, (q + 1) * order.length ~/ 5);
    quintiles.add({
      'probFrom': probs[part.first],
      'probTo': probs[part.last],
      'avgForwardReturn': part.map((i) => test[i].fwd).reduce((a, b) => a + b) / part.length,
      'upRate': part.where((i) => labels[i] == 1).length / part.length,
    });
  }

  final backtest = runBacktest(test, model);
  final market = marketStats(histories);

  // --- Эцсийн загвар: бүх өгөгдлөөр дахин сургана ---------------------------
  final finalModel = LogisticModel.train(
    [for (final s in samples) s.x],
    [for (final s in samples) s.y],
    featureNames: FeatureExtractor.names,
  );
  final metrics = <String, dynamic>{
    'trainedAt': DateTime.now().toIso8601String(),
    'horizonDays': horizonDays,
    'stocks': histories.length,
    'samples': samples.length,
    'trainSamples': train.length,
    'testSamples': test.length,
    'testPeriodStart': testStart.toIso8601String().substring(0, 10),
    'trainAuc': _r(trainAuc),
    'testAuc': _r(auc),
    'testAccuracy': _r(accuracy),
    'baselineAccuracy': _r(baseline),
    'testBaseRateUp': _r(baseRate),
    // Апп энэ утгаас дээш магадлалыг "дунджаас сайн" гэж үзнэ.
    'baseRateUp': _r(samples.where((x) => x.y == 1).length / samples.length),
    'quintiles': [
      for (final q in quintiles) {for (final e in q.entries) e.key: _r(e.value)}
    ],
    'backtest': backtest,
    // Зорилгын төлөвлөгчид: MSE-ийн тэнцүү жинтэй хувьцааны сарын өгөөж
    'market': market,
  };
  final deployed = finalModel.withMetrics(metrics);

  Directory('assets/ai').createSync(recursive: true);
  File('assets/ai/advisor_model.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(deployed.toJson()));

  // --- Өнөөдрийн дохио -------------------------------------------------------
  final signals = <StockSignal>[];
  final skipped = <String>[];
  for (final e in histories.entries) {
    final bars = e.value;
    final i = bars.length - 1;
    final x = FeatureExtractor.compute(bars, i);
    if (x == null) {
      skipped.add(e.key);
      continue;
    }
    final contrib = deployed.contributions(x);
    final top = contrib.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    signals.add(StockSignal(
      symbol: e.key,
      name: names[e.key]!,
      category: categories[e.key]!,
      date: bars[i].date,
      price: bars[i].close,
      probUp: deployed.predict(x),
      dailyVol: x[4],
      ret20: x[1],
      ret60: x[2],
      drawdown60: x[8],
      liquidity: x[10],
      rsi: (x[5] + 0.5) * 100,
      drivers: {for (final t in top) t.key: t.value},
      features: {
        for (var k = 0; k < FeatureExtractor.names.length; k++)
          FeatureExtractor.names[k]: x[k],
      },
    ));
  }
  signals.sort((a, b) => b.probUp.compareTo(a.probUp));
  final corr = correlationMatrix(histories, [for (final s in signals) s.symbol]);
  final set = SignalSet(
    generatedAt: DateTime.now(),
    signals: signals,
    corrSymbols: [for (final s in signals) s.symbol],
    correlation: corr,
    modelMetrics: {
      for (final k in ['trainedAt', 'testAuc', 'testAccuracy', 'baselineAccuracy', 'baseRateUp', 'horizonDays', 'stocks', 'samples'])
        k: metrics[k],
      'market': market,
      'backtest': {
        for (final k in ['months', 'strategyTotalReturn', 'benchmarkTotalReturn', 'monthsBeatBenchmark'])
          k: backtest[k],
      },
    },
  );
  File('assets/ai/signals.json').writeAsStringSync(jsonEncode(set.toJson()));

  writeReport(metrics, deployed, signals, skipped);

  stdout.writeln('');
  stdout.writeln('Тест AUC: ${auc.toStringAsFixed(3)} (сургалт ${trainAuc.toStringAsFixed(3)})');
  stdout.writeln('Тест нарийвчлал: ${(accuracy * 100).toStringAsFixed(1)}% '
      '(суурь ${(baseline * 100).toStringAsFixed(1)}%)');
  for (final q in quintiles) {
    stdout.writeln('  p ${q['probFrom']!.toStringAsFixed(2)}–${q['probTo']!.toStringAsFixed(2)}: '
        'дундаж өгөөж ${(q['avgForwardReturn']! * 100).toStringAsFixed(2)}%, '
        'өссөн ${(q['upRate']! * 100).toStringAsFixed(0)}%');
  }
  stdout.writeln('Backtest ${backtest['months']} сар: стратеги '
      '${(backtest['strategyTotalReturn'] * 100).toStringAsFixed(1)}%, '
      'жишиг ${(backtest['benchmarkTotalReturn'] * 100).toStringAsFixed(1)}%, '
      'жишгээс давсан сар ${backtest['monthsBeatBenchmark']}');
  stdout.writeln('Дохио: ${signals.length} хувьцаа (алгассан: ${skipped.join(', ')})');
  stdout.writeln('Зах зээл (${market['since']}–, ${market['months']} сар): '
      'жилийн өгөөж ${((market['annualReturn'] as double) * 100).toStringAsFixed(1)}%, '
      'хэлбэлзэл ${((market['annualVol'] as double) * 100).toStringAsFixed(1)}%');
}

/// Сар бүрийн эхэнд хөрвөх чадвартай хувьцаанаас загварын магадлал хамгийн
/// өндөр 5-ыг тэнцүү жинтэй авч 30 хоног барина. Жишиг: бүх хөрвөх чадвартай
/// хувьцааг тэнцүү жинтэй барих. (Шимтгэл тооцоогүй.)
/// MSE-ийн I, II ангиллын хувьцааны тэнцүү жинтэй (сар бүр тэнцвэржүүлсэн)
/// сарын өгөөжийн статистик. Зорилгын төлөвлөгчийн Monte Carlo-д ашиглана.
Map<String, dynamic> marketStats(Map<String, List<MseDailyBar>> histories,
    {int years = 10}) {
  final since = DateTime(DateTime.now().year - years, DateTime.now().month);
  // хувьцаа → (сарын түлхүүр → тухайн сарын сүүлийн бар)
  final monthEnd = <String, Map<int, MseDailyBar>>{};
  for (final e in histories.entries) {
    final m = <int, MseDailyBar>{};
    for (final b in e.value) {
      if (b.date.isBefore(since)) continue;
      m[b.date.year * 12 + b.date.month - 1] = b;
    }
    monthEnd[e.key] = m;
  }
  final keys = monthEnd.values.expand((m) => m.keys).toSet().toList()..sort();
  final monthly = <double>[];
  for (var i = 1; i < keys.length; i++) {
    final prevKey = keys[i] - 1;
    final rets = <double>[];
    for (final m in monthEnd.values) {
      final a = m[prevKey], b = m[keys[i]];
      if (a == null || b == null || a.close <= 0) continue;
      final r = b.close / a.close - 1;
      if (r.abs() <= 0.6) rets.add(r); // хувьцаа хуваах зэрэг гажуудлыг хасна
    }
    if (rets.length >= 8) monthly.add(rets.reduce((x, y) => x + y) / rets.length);
  }
  final n = monthly.length;
  final mean = monthly.reduce((a, b) => a + b) / n;
  final vol = math.sqrt(
      monthly.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / (n - 1));
  final growth = monthly.fold<double>(1, (g, r) => g * (1 + r));
  return {
    'since': '${since.year}-${since.month.toString().padLeft(2, '0')}',
    'months': n,
    'monthlyMean': _r(mean),
    'monthlyVol': _r(vol),
    'annualReturn': _r(math.pow(growth, 12 / n) - 1),
    'annualVol': _r(vol * math.sqrt(12)),
  };
}

Map<String, dynamic> runBacktest(List<Sample> test, LogisticModel model) {
  final byMonth = <String, Map<String, Sample>>{};
  for (final s in test) {
    if (s.x[10] < 0.6) continue; // хөрвөх чадвар
    final key = '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}';
    final m = byMonth.putIfAbsent(key, () => {});
    final prev = m[s.symbol];
    if (prev == null || s.date.isBefore(prev.date)) m[s.symbol] = s;
  }
  final months = byMonth.keys.toList()..sort();
  var strat = 1.0, bench = 1.0, beat = 0;
  final rows = <Map<String, dynamic>>[];
  for (final month in months) {
    final list = byMonth[month]!.values.toList();
    if (list.length < 8) continue;
    list.sort((a, b) => model.predict(b.x).compareTo(model.predict(a.x)));
    final top = list.take(5).toList();
    final sr = top.map((s) => s.fwd).reduce((a, b) => a + b) / top.length;
    final br = list.map((s) => s.fwd).reduce((a, b) => a + b) / list.length;
    strat *= 1 + sr;
    bench *= 1 + br;
    if (sr > br) beat++;
    rows.add({'month': month, 'strategy': _r(sr), 'benchmark': _r(br), 'picks': [for (final s in top) s.symbol]});
  }
  return {
    'months': rows.length,
    'strategyTotalReturn': _r(strat - 1),
    'benchmarkTotalReturn': _r(bench - 1),
    'monthsBeatBenchmark': beat,
    'rows': rows,
  };
}

/// Сүүлийн 1 жилийн өдрийн log өгөөжийн корреляци (нийтлэг өдрүүдээр).
List<List<double>> correlationMatrix(Map<String, List<MseDailyBar>> h, List<String> syms) {
  final since = DateTime.now().subtract(const Duration(days: 365));
  final rets = <String, Map<DateTime, double>>{};
  for (final s in syms) {
    final bars = h[s]!;
    final m = <DateTime, double>{};
    for (var i = 1; i < bars.length; i++) {
      if (bars[i].date.isBefore(since)) continue;
      final r = math.log(bars[i].close / bars[i - 1].close);
      if (r.abs() <= FeatureExtractor.anomalyLogReturn) m[bars[i].date] = r;
    }
    rets[s] = m;
  }
  final n = syms.length;
  final out = List.generate(n, (_) => List<double>.filled(n, 0));
  for (var i = 0; i < n; i++) {
    out[i][i] = 1;
    for (var j = i + 1; j < n; j++) {
      final a = rets[syms[i]]!, b = rets[syms[j]]!;
      final common = a.keys.where(b.containsKey).toList();
      double c = 0.3; // хангалттай өгөгдөлгүй бол болгоомжтой таамаг
      if (common.length >= 30) {
        final xa = [for (final d in common) a[d]!];
        final xb = [for (final d in common) b[d]!];
        final ma = xa.reduce((p, q) => p + q) / xa.length;
        final mb = xb.reduce((p, q) => p + q) / xb.length;
        var cov = 0.0, va = 0.0, vb = 0.0;
        for (var k = 0; k < xa.length; k++) {
          cov += (xa[k] - ma) * (xb[k] - mb);
          va += (xa[k] - ma) * (xa[k] - ma);
          vb += (xb[k] - mb) * (xb[k] - mb);
        }
        if (va > 0 && vb > 0) c = cov / math.sqrt(va * vb);
      }
      out[i][j] = c;
      out[j][i] = c;
    }
  }
  return out;
}

void writeReport(Map<String, dynamic> m, LogisticModel model, List<StockSignal> signals, List<String> skipped) {
  final b = StringBuffer()
    ..writeln('# AI зөвлөхийн загварын тайлан')
    ..writeln()
    ..writeln('`dart run tool/train_advisor.dart` автоматаар үүсгэв (${(m['trainedAt'] as String).substring(0, 16)}).')
    ..writeln()
    ..writeln('## Өгөгдөл')
    ..writeln('- Эх сурвалж: open.mse.mn, I ба II ангиллын ${m['stocks']} хувьцааны өдөр тутмын арилжаа')
    ..writeln('- Нийт жишээ: ${m['samples']} (сургалт ${m['trainSamples']}, тест ${m['testSamples']})')
    ..writeln('- Тестийн үе: ${m['testPeriodStart']}-ээс хойш (сургалтаас ${horizonDays + 5} хоногийн зайтай)')
    ..writeln('- Зорилт: дараагийн $horizonDays хоногт ханш өсөх эсэх (0/1)')
    ..writeln()
    ..writeln('## Загвар')
    ..writeln('Логистик регресс (өөрсдөө бичсэн, `lib/ai_engine/logistic_model.dart`), ${model.featureNames.length} шинж, L2 регуляризаци.')
    ..writeln()
    ..writeln('| Шинж | Жин (стандартчилсан) |')
    ..writeln('|---|---|');
  for (var k = 0; k < model.featureNames.length; k++) {
    b.writeln('| ${model.featureNames[k]} | ${model.weights[k].toStringAsFixed(4)} |');
  }
  b
    ..writeln()
    ..writeln('## Тестийн үр дүн')
    ..writeln('| Үзүүлэлт | Утга |')
    ..writeln('|---|---|')
    ..writeln('| ROC AUC (тест) | ${m['testAuc']} |')
    ..writeln('| ROC AUC (сургалт) | ${m['trainAuc']} |')
    ..writeln('| Нарийвчлал (тест) | ${(m['testAccuracy'] * 100).toStringAsFixed(1)}% |')
    ..writeln('| Суурь нарийвчлал (үргэлж олонх ангилал) | ${(m['baselineAccuracy'] * 100).toStringAsFixed(1)}% |')
    ..writeln()
    ..writeln('### Магадлалын бүлэг тус бүрийн бодит үр дүн')
    ..writeln('| Магадлал | Дундаж $horizonDays хоногийн өгөөж | Өссөн хувь |')
    ..writeln('|---|---|---|');
  for (final q in m['quintiles'] as List) {
    b.writeln('| ${(q['probFrom'] as double).toStringAsFixed(2)}–${(q['probTo'] as double).toStringAsFixed(2)} '
        '| ${((q['avgForwardReturn'] as double) * 100).toStringAsFixed(2)}% '
        '| ${((q['upRate'] as double) * 100).toStringAsFixed(0)}% |');
  }
  final bt = m['backtest'] as Map<String, dynamic>;
  b
    ..writeln()
    ..writeln('### Backtest (сар бүр шилдэг 5 хувьцаа, тэнцүү жин, шимтгэлгүй)')
    ..writeln('- Сарын тоо: ${bt['months']}')
    ..writeln('- Стратегийн нийт өгөөж: ${((bt['strategyTotalReturn'] as double) * 100).toStringAsFixed(1)}%')
    ..writeln('- Жишиг (бүх хувьцаа тэнцүү жин): ${((bt['benchmarkTotalReturn'] as double) * 100).toStringAsFixed(1)}%')
    ..writeln('- Жишгээс давсан сар: ${bt['monthsBeatBenchmark']}/${bt['months']}')
    ..writeln()
    ..writeln('## Өнөөдрийн дохио (эхний 10)')
    ..writeln('| Хувьцаа | Өсөх магадлал | 60 өдрийн өгөөж | Жилийн хэлбэлзэл |')
    ..writeln('|---|---|---|---|');
  for (final s in signals.take(10)) {
    b.writeln('| ${s.symbol} | ${(s.probUp * 100).toStringAsFixed(1)}% | ${(s.ret60 * 100).toStringAsFixed(1)}% | ${(s.annualVol * 100).toStringAsFixed(0)}% |');
  }
  if (skipped.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Түүх хангалтгүй эсвэл сүүлийн 60 өдөрт гажуудалтай тул алгассан: ${skipped.join(', ')}');
  }
  b
    ..writeln()
    ..writeln('## Хязгаарлалт')
    ..writeln('- MSE-ийн олон хувьцаа ховор арилжаалагддаг тул таамаглалын нарийвчлал хязгаарлагдмал.')
    ..writeln('- Backtest шимтгэл, үнийн нөлөө (slippage), хөрвөх чадварын хязгаарыг тооцоогүй.')
    ..writeln('- Түүхэн үр дүн ирээдүйн өгөөжийг баталгаажуулахгүй.');
  Directory('docs').createSync(recursive: true);
  File('docs/ai_model_report.md').writeAsStringSync(b.toString());
}

double _r(num v) => (v * 10000).roundToDouble() / 10000;

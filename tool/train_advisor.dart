// AI зөвлөхийн загварыг сургах, шударгаар үнэлэх, апп-д зориулсан дохио гаргах.
//
//   dart run tool/build_dataset.dart   # (эхлээд) MSE-ийн түүх + санхүүгийн тайлан
//   dart run tool/train_advisor.dart   # сургаад assets/ai/*.json бичнэ
//
// Арга зүй:
//   * Зорилт: дараагийн 30 хоногт тухайн хувьцаа тэр өдрийн бусад хувьцааны
//     дунджаас ИЛҮҮ өсөх эсэх (харьцангуй) — зах зээлийн ерөнхий хөдөлгөөнийг
//     хасаж, хувьцааг эрэмбэлэх чадварыг л хэмжинэ.
//   * Walk-forward: 2024 оноос хойш улирал бүр зөвхөн өнгөрсөн өгөгдлөөр дахин
//     сургаж, дараагийн улирлыг таамаглана (бодит хэрэглээг дуурайна).
//   * Логистик регресс ба GBM-ийг ижил нөхцөлд харьцуулж, сайныг нь сонгоно.
//   * Backtest: брокерийн шимтгэл + үнийн зөрүү, хөрвөх чадварын шүүлттэй.
//   * Platt calibration: магадлалыг загвар хараагүй таамаг дээр тохируулна.
//
// Гаралт:
//   assets/ai/advisor_model.json, assets/ai/signals.json, docs/ai_model_report.md,
//   tool/data/signal_log.json (өдөр бүрийн дохионы бүртгэл → бодит гүйцэтгэл)
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:jvgee_diplom/ai_engine/features.dart';
import 'package:jvgee_diplom/ai_engine/fundamentals.dart';
import 'package:jvgee_diplom/ai_engine/gbm.dart';
import 'package:jvgee_diplom/ai_engine/logistic_model.dart';
import 'package:jvgee_diplom/ai_engine/signals.dart';
import 'package:jvgee_diplom/models/mse_quote.dart';

const horizonDays = 30;
const embargoDays = horizonDays + 5;

/// Дохио гарснаас хойш хэдэн арилжааны өдрийн дараа авах вэ.
const entryLag = 1;
final walkForwardStart = DateTime(2024, 1, 1);

/// Нэг талын гүйлгээний зардал: брокерийн шимтгэл + авах/зарах үнийн зөрүү (таамаг).
const feePerSide = 0.005;

/// Backtest-д хамрах өдрийн дундаж арилжааны доод дүн (₮) — бодитоор авч болох.
const minTurnover = 2e6;
const topN = 5;

class Sample {
  final String symbol;
  final DateTime date;
  final List<double> x;
  final double fwd;
  final double turnover;
  double excess = 0;
  int y = 0;
  Sample(this.symbol, this.date, this.x, this.fwd, this.turnover);
}

typedef Trainer = SignalModel Function(List<List<double>> xs, List<int> ys);

final trainers = <String, Trainer>{
  'logistic': (xs, ys) =>
      LogisticModel.train(xs, ys, featureNames: FeatureExtractor.names),
  'gbm': (xs, ys) =>
      GbmModel.train(xs, ys, featureNames: FeatureExtractor.names),
};

Future<void> main() async {
  final sw = Stopwatch()..start();
  // --- Өгөгдөл ----------------------------------------------------------------
  final securities = [
    for (final s in jsonDecode(File('tool/data/securities.json').readAsStringSync()) as List)
      s as Map<String, dynamic>
  ];
  final histories = <String, List<MseDailyBar>>{};
  final fundamentals = <String, FundamentalsSeries>{};
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
    final ff = File('tool/data/fundamentals/$sym.json');
    if (ff.existsSync()) {
      fundamentals[sym] = FundamentalsSeries([
        for (final r in jsonDecode(ff.readAsStringSync()) as List)
          FinancialReport.fromJson(r as Map<String, dynamic>)
      ]);
    }
  }
  final market = MarketIndex.fromHistories(histories.values);
  stdout.writeln('Хувьцаа: ${histories.length}, санхүүгийн тайлантай: ${fundamentals.length}');

  // --- Датасет ----------------------------------------------------------------
  final raw = <Sample>[];
  for (final e in histories.entries) {
    final bars = e.value;
    for (var i = FeatureExtractor.lookback; i < bars.length; i++) {
      final x = FeatureExtractor.compute(bars, i,
          market: market, fundamentals: fundamentals[e.key]);
      if (x == null) continue;
      // Дараагийн арилжааны өдөр авна гэж тооцно (дохионы өдрийн хаалтаар биш)
      final fwd = FeatureExtractor.forwardReturn(bars, i,
          horizonDays: horizonDays, entryLag: entryLag);
      if (fwd == null) continue;
      raw.add(Sample(e.key, bars[i].date, x, fwd,
          FeatureExtractor.averageTurnover(bars, i)));
    }
  }
  // Зөвхөн бодитоор авч болох (хөрвөх чадвартай) хувьцаан дээр сургана.
  // Ховор арилжаалагддаг хувьцааны "хуучирсан" ханш загварыг төөрөгдүүлж,
  // хөрвөх чадварыг сөрөг хүчин зүйл мэтээр сургадаг байсан.
  final investable =
      raw.where((s) => s.x[10] >= 0.6 && s.turnover >= minTurnover);
  // Харьцангуй шошго: тухайн өдрийн (хөрвөх чадвартай) хувьцааны дундаж
  // ирээдүйн өгөөжөөс илүү эсэх
  final byDate = <DateTime, List<Sample>>{};
  for (final s in investable) {
    byDate.putIfAbsent(s.date, () => []).add(s);
  }
  final samples = <Sample>[];
  for (final group in byDate.values) {
    if (group.length < 5) continue;
    final mean = group.map((s) => s.fwd).reduce((a, b) => a + b) / group.length;
    for (final s in group) {
      s.excess = s.fwd - mean;
      s.y = s.excess > 0 ? 1 : 0;
      samples.add(s);
    }
  }
  samples.sort((a, b) => a.date.compareTo(b.date));
  final baseRate = samples.where((s) => s.y == 1).length / samples.length;
  stdout.writeln('Жишээ: ${samples.length} (дунджаас илүү: ${(baseRate * 100).toStringAsFixed(1)}%)');

  // --- Walk-forward -----------------------------------------------------------
  final lastDate = samples.last.date;
  final quarters = <DateTime>[];
  for (var q = walkForwardStart; q.isBefore(lastDate);
      q = DateTime(q.year, q.month + 3)) {
    quarters.add(q);
  }
  final oos = {for (final m in trainers.keys) m: <int, double>{}}; // index → margin
  for (final q in quarters) {
    final qEnd = DateTime(q.year, q.month + 3);
    final cutoff = q.subtract(const Duration(days: embargoDays));
    final trainIdx = <int>[], testIdx = <int>[];
    for (var i = 0; i < samples.length; i++) {
      final d = samples[i].date;
      if (d.isBefore(cutoff)) {
        trainIdx.add(i);
      } else if (!d.isBefore(q) && d.isBefore(qEnd)) {
        testIdx.add(i);
      }
    }
    if (testIdx.isEmpty) continue;
    for (final e in trainers.entries) {
      final model = e.value([for (final i in trainIdx) samples[i].x],
          [for (final i in trainIdx) samples[i].y]);
      for (final i in testIdx) {
        oos[e.key]![i] = model.margin(samples[i].x);
      }
    }
    stdout.writeln('  ${_d(q)}: сургалт ${trainIdx.length}, тест ${testIdx.length} (${sw.elapsed.inSeconds}s)');
  }

  final evaluation = <String, Map<String, dynamic>>{};
  for (final m in trainers.keys) {
    final idx = oos[m]!.keys.toList()..sort();
    evaluation[m] = evaluate(
      [for (final i in idx) samples[i]],
      [for (final i in idx) oos[m]![i]!],
    );
  }
  // Хувьцаа сонгоход эрэмбэлэх чадвар (Rank IC) хамгийн чухал. Ялгаа бага бол
  // илүү энгийн, тайлбарлахад хялбар логистикийг давуу эрхтэй сонгоно.
  final best = (evaluation['gbm']!['rankIc'] as double) >
          (evaluation['logistic']!['rankIc'] as double) + 0.005
      ? 'gbm'
      : 'logistic';

  final bestIdx = oos[best]!.keys.toList()..sort();
  final calibration = PlattCalibration.fit(
    [for (final i in bestIdx) oos[best]![i]!],
    [for (final i in bestIdx) samples[i].y],
  );
  final calTable = calibrationTable(
    [for (final i in bestIdx) calibration.apply(oos[best]![i]!)],
    [for (final i in bestIdx) samples[i].y],
  );
  stdout.writeln('Сонгосон загвар: $best (${sw.elapsed.inSeconds}s)');

  // --- Эцсийн загвар: бүх өгөгдлөөр -------------------------------------------
  final finalModel = trainers[best]!(
      [for (final s in samples) s.x], [for (final s in samples) s.y]);
  final marketInfo = marketStats(histories);

  final metrics = <String, dynamic>{
    'trainedAt': DateTime.now().toIso8601String(),
    'target': 'excess', // зах зээлийн дунджаас илүү өсөх магадлал
    'horizonDays': horizonDays,
    'stocks': histories.length,
    'withFundamentals': fundamentals.length,
    'samples': samples.length,
    'features': FeatureExtractor.names.length,
    'modelType': best,
    'baseRateUp': _r(baseRate),
    'walkForwardStart': _d(walkForwardStart),
    'feePerSide': feePerSide,
    'minTurnover': minTurnover,
    'evaluation': evaluation,
    'testAuc': evaluation[best]!['auc'],
    'rankIc': evaluation[best]!['rankIc'],
    'calibration': {...calibration.toJson(), 'table': calTable},
    'market': marketInfo,
  };
  final modelJson = {
    ...finalModel.toJson(),
    'calibration': calibration.toJson(),
    'metrics': metrics,
  };
  Directory('assets/ai').createSync(recursive: true);
  File('assets/ai/advisor_model.json').writeAsStringSync(jsonEncode(modelJson));

  // --- Өнөөдрийн дохио --------------------------------------------------------
  final signals = <StockSignal>[];
  final skipped = <String>[];
  for (final e in histories.entries) {
    final bars = e.value;
    final i = bars.length - 1;
    final x = FeatureExtractor.compute(bars, i,
        market: market, fundamentals: fundamentals[e.key]);
    if (x == null) {
      skipped.add(e.key);
      continue;
    }
    final contrib = finalModel.contributions(x);
    signals.add(StockSignal(
      symbol: e.key,
      name: names[e.key]!,
      category: categories[e.key]!,
      date: bars[i].date,
      price: bars[i].close,
      probUp: calibration.apply(finalModel.margin(x)),
      dailyVol: x[4],
      ret20: x[1],
      ret60: x[2],
      drawdown60: x[8],
      liquidity: x[10],
      rsi: (x[5] + 0.5) * 100,
      avgTurnover: FeatureExtractor.averageTurnover(bars, i),
      sector: SectorGuess.of(names[e.key]!),
      // Тохируулгын налуугаар (a) үржүүлж, нөлөөг тохируулсан магадлалтай нийцүүлнэ
      drivers: {for (final c in contrib.entries) c.key: c.value * calibration.a},
      features: {
        for (var k = 0; k < FeatureExtractor.names.length; k++)
          FeatureExtractor.names[k]: x[k],
      },
    ));
  }
  signals.sort((a, b) => b.probUp.compareTo(a.probUp));

  // --- Бодит гүйцэтгэлийн бүртгэл ---------------------------------------------
  final trackRecord = updateSignalLog(signals, histories);

  final corr = correlationMatrix(histories, [for (final s in signals) s.symbol]);
  final set = SignalSet(
    generatedAt: DateTime.now(),
    signals: signals,
    corrSymbols: [for (final s in signals) s.symbol],
    correlation: corr,
    modelMetrics: {
      for (final k in [
        'trainedAt', 'target', 'modelType', 'testAuc', 'rankIc', 'baseRateUp',
        'horizonDays', 'stocks', 'samples', 'features', 'feePerSide', 'market',
      ])
        k: metrics[k],
      'backtest': {
        for (final e in (evaluation[best]!['backtest'] as Map<String, dynamic>).entries)
          if (e.key != 'rows') e.key: e.value,
      },
      'calibrationTable': calTable,
      'trackRecord': trackRecord,
    },
  );
  File('assets/ai/signals.json').writeAsStringSync(jsonEncode(set.toJson()));

  writeReport(metrics, finalModel, signals, skipped, trackRecord);

  stdout.writeln('');
  for (final m in trainers.keys) {
    final e = evaluation[m]!;
    final bt = e['backtest'] as Map<String, dynamic>;
    stdout.writeln('$m: AUC ${e['auc']}, Rank IC ${e['rankIc']}, '
        'backtest (шимтгэлтэй) ${_pct(bt['strategyTotalReturn'])} vs '
        'жишиг ${_pct(bt['benchmarkTotalReturn'])}, сар ${bt['monthsBeatBenchmark']}/${bt['months']}, '
        't=${bt['excessTStat']}');
  }
  stdout.writeln('Сонгосон: $best, calibration a=${calibration.a.toStringAsFixed(3)} '
      'b=${calibration.b.toStringAsFixed(3)}');
  stdout.writeln('Дохио: ${signals.length} хувьцаа (алгассан: ${skipped.join(', ')})');
  stdout.writeln('Бодит бүртгэл: ${trackRecord['logged']} өдөр, үнэлэгдсэн ${trackRecord['evaluated']}');
  stdout.writeln('Зах зээл: жилийн өгөөж ${_pct(marketInfo['annualReturn'])}, '
      'хэлбэлзэл ${_pct(marketInfo['annualVol'])}');
  stdout.writeln('Нийт хугацаа: ${sw.elapsed.inSeconds}s');
}

/// Загвар хараагүй таамаг дээрх үнэлгээ.
Map<String, dynamic> evaluate(List<Sample> s, List<double> margins) {
  final auc = rocAuc(margins, [for (final x in s) x.y]);
  // Өдөр бүрийн Rank IC-ийн дундаж (таамаг ба харьцангуй өгөөжийн эрэмбийн корреляци)
  final byDate = <DateTime, List<int>>{};
  for (var i = 0; i < s.length; i++) {
    byDate.putIfAbsent(s[i].date, () => []).add(i);
  }
  final ics = <double>[];
  for (final idx in byDate.values) {
    if (idx.length < 8) continue;
    ics.add(spearman([for (final i in idx) margins[i]], [for (final i in idx) s[i].excess]));
  }
  final ic = ics.isEmpty ? 0.0 : ics.reduce((a, b) => a + b) / ics.length;
  return {
    'auc': _r(auc),
    'rankIc': _r(ic),
    'samples': s.length,
    'backtest': runBacktest(s, margins),
  };
}

/// Сар бүрийн эхэнд хөрвөх чадвартай хувьцаанаас таамаг хамгийн өндөр [topN]-ийг
/// тэнцүү жинтэй авч 30 хоног барина. Шимтгэлийг солигдсон хувьцааны хэмжээгээр
/// тооцно. Жишиг: бүх хөрвөх чадвартай хувьцааг тэнцүү жинтэй барих.
Map<String, dynamic> runBacktest(List<Sample> s, List<double> margins) {
  final byMonth = <String, Map<String, int>>{};
  for (var i = 0; i < s.length; i++) {
    final x = s[i];
    if (x.x[10] < 0.6 || x.turnover < minTurnover) continue;
    final key = '${x.date.year}-${x.date.month.toString().padLeft(2, '0')}';
    final m = byMonth.putIfAbsent(key, () => {});
    final prev = m[x.symbol];
    if (prev == null || x.date.isBefore(s[prev].date)) m[x.symbol] = i;
  }
  final months = byMonth.keys.toList()..sort();
  var stratEq = 1.0, benchEq = 1.0, stratPeak = 1.0, benchPeak = 1.0;
  var stratDd = 0.0, benchDd = 0.0, grossS = 1.0;
  var beat = 0;
  Set<String> prevS = {}, prevB = {};
  final excess = <double>[], stratRets = <double>[], turnovers = <double>[];
  final rows = <Map<String, dynamic>>[];
  for (final month in months) {
    final idx = byMonth[month]!.values.toList();
    if (idx.length < 8) continue;
    idx.sort((a, b) => margins[b].compareTo(margins[a]));
    final picks = idx.take(topN).toList();
    final pickSet = {for (final i in picks) s[i].symbol};
    final allSet = {for (final i in idx) s[i].symbol};
    double mean(List<int> l) =>
        l.map((i) => s[i].fwd).reduce((a, b) => a + b) / l.length;
    final gs = mean(picks), gb = mean(idx);
    final turnS = prevS.isEmpty ? 1.0 : pickSet.difference(prevS).length / pickSet.length;
    final turnB = prevB.isEmpty ? 1.0 : allSet.difference(prevB).length / allSet.length;
    final costS = prevS.isEmpty ? feePerSide : 2 * feePerSide * turnS;
    final costB = prevB.isEmpty ? feePerSide : 2 * feePerSide * turnB;
    final ns = gs - costS, nb = gb - costB;
    grossS *= 1 + gs;
    stratEq *= 1 + ns;
    benchEq *= 1 + nb;
    stratPeak = math.max(stratPeak, stratEq);
    benchPeak = math.max(benchPeak, benchEq);
    stratDd = math.min(stratDd, stratEq / stratPeak - 1);
    benchDd = math.min(benchDd, benchEq / benchPeak - 1);
    if (ns > nb) beat++;
    excess.add(ns - nb);
    stratRets.add(ns);
    turnovers.add(turnS);
    prevS = pickSet;
    prevB = allSet;
    rows.add({
      'month': month,
      'strategy': _r(ns),
      'benchmark': _r(nb),
      'picks': pickSet.toList(),
    });
  }
  final n = excess.length;
  double meanOf(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  double stdOf(List<double> v) {
    if (v.length < 2) return 0;
    final m = meanOf(v);
    return math.sqrt(
        v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (v.length - 1));
  }

  final ex = meanOf(excess), exSd = stdOf(excess);
  final years = n / 12;
  return {
    'months': n,
    'strategyTotalReturn': _r(stratEq - 1),
    'strategyGrossReturn': _r(grossS - 1),
    'benchmarkTotalReturn': _r(benchEq - 1),
    'strategyCagr': n == 0 ? 0.0 : _r(math.pow(stratEq, 1 / years) - 1),
    'benchmarkCagr': n == 0 ? 0.0 : _r(math.pow(benchEq, 1 / years) - 1),
    'strategyAnnualVol': _r(stdOf(stratRets) * math.sqrt(12)),
    'strategyMaxDrawdown': _r(stratDd),
    'benchmarkMaxDrawdown': _r(benchDd),
    'monthsBeatBenchmark': beat,
    'meanMonthlyExcess': _r(ex),
    'excessTStat': exSd == 0 ? 0.0 : _r(ex / (exSd / math.sqrt(n))),
    'avgTurnover': _r(meanOf(turnovers)),
    'rows': rows,
  };
}

/// Тохируулсан магадлалын 10 бүлэг: таамаг ба бодит давтамж.
List<Map<String, double>> calibrationTable(List<double> probs, List<int> ys) {
  final order = List<int>.generate(probs.length, (i) => i)
    ..sort((a, b) => probs[a].compareTo(probs[b]));
  final out = <Map<String, double>>[];
  for (var q = 0; q < 10; q++) {
    final part = order.sublist(q * order.length ~/ 10, (q + 1) * order.length ~/ 10);
    if (part.isEmpty) continue;
    out.add({
      'predicted': _r(part.map((i) => probs[i]).reduce((a, b) => a + b) / part.length),
      'actual': _r(part.where((i) => ys[i] == 1).length / part.length),
    });
  }
  return out;
}

/// Өдөр бүрийн дохиог бүртгэж, 30+ хоногийн дараа бодит үр дүнг үнэлнэ.
Map<String, dynamic> updateSignalLog(
    List<StockSignal> signals, Map<String, List<MseDailyBar>> histories) {
  final file = File('tool/data/signal_log.json');
  final log = file.existsSync()
      ? [
          for (final e in jsonDecode(file.readAsStringSync()) as List)
            e as Map<String, dynamic>
        ]
      : <Map<String, dynamic>>[];
  final dataDate =
      signals.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);
  final key = _d(dataDate);
  final liquid = signals
      .where((s) => s.liquidity >= 0.6 && s.avgTurnover >= minTurnover)
      .toList()
    ..sort((a, b) => b.probUp.compareTo(a.probUp));
  if (!log.any((e) => e['date'] == key)) {
    log.add({
      'date': key,
      'top': [for (final s in liquid.take(topN)) s.symbol],
      'universe': [for (final s in liquid) s.symbol],
    });
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(log));

  double? priceOn(String sym, DateTime d, {bool after = false}) {
    final bars = histories[sym];
    if (bars == null || bars.isEmpty) return null;
    if (after) {
      for (final b in bars) {
        if (!b.date.isBefore(d)) return b.close;
      }
      return null;
    }
    double? p;
    for (final b in bars) {
      if (b.date.isAfter(d)) break;
      p = b.close;
    }
    return p;
  }

  final lastBar = histories.values
      .map((b) => b.last.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final evaluated = <Map<String, dynamic>>[];
  for (final e in log) {
    final d = DateTime.parse(e['date'] as String);
    final end = d.add(const Duration(days: horizonDays));
    if (end.isAfter(lastBar)) continue;
    double? avgRet(List syms) {
      final rets = <double>[];
      for (final s in syms) {
        final a = priceOn(s as String, d), b = priceOn(s, end, after: true);
        if (a != null && b != null && a > 0) rets.add(b / a - 1);
      }
      return rets.isEmpty ? null : rets.reduce((x, y) => x + y) / rets.length;
    }

    final top = avgRet(e['top'] as List), all = avgRet(e['universe'] as List);
    if (top == null || all == null) continue;
    evaluated.add({
      'date': e['date'],
      'top': _r(top),
      'universe': _r(all),
      'excess': _r(top - all),
    });
  }
  final ex = [for (final e in evaluated) e['excess'] as double];
  return {
    'since': log.isEmpty ? null : log.first['date'],
    'logged': log.length,
    'evaluated': evaluated.length,
    'meanExcess': ex.isEmpty ? null : _r(ex.reduce((a, b) => a + b) / ex.length),
    'hitRate': ex.isEmpty ? null : _r(ex.where((x) => x > 0).length / ex.length),
    'recent': evaluated.length <= 12
        ? evaluated
        : evaluated.sublist(evaluated.length - 12),
  };
}

/// MSE-ийн I, II ангиллын хувьцааны тэнцүү жинтэй (сар бүр тэнцвэржүүлсэн)
/// сарын өгөөжийн статистик ба цуврал (зорилгын төлөвлөгчийн bootstrap-д).
Map<String, dynamic> marketStats(Map<String, List<MseDailyBar>> histories,
    {int years = 10}) {
  final since = DateTime(DateTime.now().year - years, DateTime.now().month);
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
      if (r.abs() <= 0.6) rets.add(r);
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
    'monthlySeries': [for (final r in monthly) _r(r)],
  };
}

/// Сүүлийн 1 жилийн өдрийн log өгөөжийн корреляци (нийтлэг өдрүүдээр).
List<List<double>> correlationMatrix(
    Map<String, List<MseDailyBar>> h, List<String> syms) {
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
      double c = 0.3;
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

void writeReport(Map<String, dynamic> m, SignalModel model,
    List<StockSignal> signals, List<String> skipped, Map<String, dynamic> track) {
  final ev = m['evaluation'] as Map<String, Map<String, dynamic>>;
  final b = StringBuffer()
    ..writeln('# AI зөвлөхийн загварын тайлан')
    ..writeln()
    ..writeln('`dart run tool/train_advisor.dart` автоматаар үүсгэв '
        '(${(m['trainedAt'] as String).substring(0, 16)}).')
    ..writeln()
    ..writeln('## Өгөгдөл ба зорилт')
    ..writeln('- Эх сурвалж: open.mse.mn — I, II ангиллын ${m['stocks']} хувьцааны өдөр '
        'тутмын арилжаа, ${m['withFundamentals']} компанийн санхүүгийн тайлан '
        '(нийтлэгдсэн огнооноос хойш л ашиглана)')
    ..writeln('- Нийт жишээ: ${m['samples']}, шинж: ${m['features']}')
    ..writeln('- **Зорилт:** дараагийн $horizonDays хоногт тухайн хувьцаа тэр өдрийн '
        'бусад хувьцааны дунджаас илүү өсөх эсэх (харьцангуй). Дохио гарсны '
        'дараагийн арилжааны өдөр авна гэж тооцсон. Суурь давтамж '
        '${_pct(m['baseRateUp'])}.')
    ..writeln()
    ..writeln('## Walk-forward үнэлгээ (${m['walkForwardStart']}-аас хойш, улирал бүр дахин сургасан)')
    ..writeln('| Загвар | AUC | Rank IC | Backtest (шимтгэлтэй) | Жишиг | CAGR | Max drawdown '
        '| Жишгээс давсан сар | Excess t-stat |')
    ..writeln('|---|---|---|---|---|---|---|---|---|');
  for (final e in ev.entries) {
    final bt = e.value['backtest'] as Map<String, dynamic>;
    b.writeln('| ${e.key}${e.key == m['modelType'] ? ' ✅' : ''} | ${e.value['auc']} '
        '| ${e.value['rankIc']} | ${_pct(bt['strategyTotalReturn'])} '
        '| ${_pct(bt['benchmarkTotalReturn'])} | ${_pct(bt['strategyCagr'])} '
        '| ${_pct(bt['strategyMaxDrawdown'])} | ${bt['monthsBeatBenchmark']}/${bt['months']} '
        '| ${bt['excessTStat']} |');
  }
  final bestBt = ev[m['modelType']]!['backtest'] as Map<String, dynamic>;
  b
    ..writeln()
    ..writeln('Backtest: сар бүр хөрвөх чадвартай (өдөрт ≥ ${_money(minTurnover)}₮ '
        'арилжаатай) хувьцаанаас шилдэг $topN-ыг тэнцүү жинтэй барина. Нэг талын '
        'зардал ${_pct(feePerSide)} (шимтгэл + үнийн зөрүү), солигдсон хувьцааны '
        'хэмжээгээр тооцсон. Шимтгэлгүй бол ${_pct(bestBt['strategyGrossReturn'])}; '
        'сарын дундаж солилт ${_pct(bestBt['avgTurnover'])}. Excess t-stat > 2 бол '
        'статистикийн хувьд итгэлтэй гэж үзнэ.')
    ..writeln()
    ..writeln('## Магадлалын тохируулга (Platt)')
    ..writeln('| Таамагласан | Бодит давтамж |')
    ..writeln('|---|---|');
  for (final row in (m['calibration'] as Map)['table'] as List) {
    b.writeln('| ${_pct(row['predicted'])} | ${_pct(row['actual'])} |');
  }
  b
    ..writeln()
    ..writeln('## Шинжүүдийн ач холбогдол (эцсийн загвар: ${m['modelType']})');
  if (model is LogisticModel) {
    b
      ..writeln('| Шинж | Жин (стандартчилсан) |')
      ..writeln('|---|---|');
    for (var k = 0; k < model.featureNames.length; k++) {
      b.writeln('| ${model.featureNames[k]} | ${model.weights[k].toStringAsFixed(4)} |');
    }
  } else if (model is GbmModel) {
    final c = model.splitCounts().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    b
      ..writeln('| Шинж | Хуваалтын тоо |')
      ..writeln('|---|---|');
    for (final e in c) {
      b.writeln('| ${e.key} | ${e.value} |');
    }
  }
  b
    ..writeln()
    ..writeln('## Бодит цагийн гүйцэтгэл (өдөр бүрийн дохионы бүртгэл)')
    ..writeln(track['evaluated'] == 0
        ? '- Бүртгэл ${track['since'] ?? 'өнөөдөр'}-аас эхэлсэн (${track['logged']} өдөр). '
            '$horizonDays хоногийн дараа үр дүн гарч эхэлнэ.'
        : '- ${track['evaluated']} өдрийн дохио үнэлэгдсэн: шилдэг $topN нь бусдаас '
            'дунджаар ${_pct(track['meanExcess'])} илүү, ${_pct(track['hitRate'])} '
            'тохиолдолд давсан.')
    ..writeln()
    ..writeln('## Өнөөдрийн дохио (эхний 10)')
    ..writeln('| Хувьцаа | Салбар | Дунджаас илүү өсөх магадлал | Өдрийн дундаж арилжаа |')
    ..writeln('|---|---|---|---|');
  for (final s in signals.take(10)) {
    b.writeln('| ${s.symbol} | ${s.sector} | ${_pct(s.probUp)} | ${_money(s.avgTurnover)}₮ |');
  }
  if (skipped.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Түүх хангалтгүй эсвэл сүүлийн 60 өдөрт гажуудалтай тул алгассан: '
          '${skipped.join(', ')}');
  }
  b
    ..writeln()
    ..writeln('## Хязгаарлалт')
    ..writeln('- MSE-ийн олон хувьцаа ховор арилжаалагддаг; таамаглалын нарийвчлал хязгаарлагдмал.')
    ..writeln('- Зардлын таамаг (${_pct(feePerSide)}/тал) брокерээс хамаарч өөр байж болно.')
    ..writeln('- Салбарыг компанийн нэрээр ойролцоолсон (MSE албан ангилал нийтэлдэггүй).')
    ..writeln('- Түүхэн үр дүн ирээдүйн өгөөжийг баталгаажуулахгүй.');
  Directory('docs').createSync(recursive: true);
  File('docs/ai_model_report.md').writeAsStringSync(b.toString());
}

double _r(num v) => (v * 10000).roundToDouble() / 10000;
String _d(DateTime d) => d.toIso8601String().substring(0, 10);
String _pct(dynamic v) => v is num ? '${(v * 100).toStringAsFixed(1)}%' : '—';
String _money(num v) {
  final s = v.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

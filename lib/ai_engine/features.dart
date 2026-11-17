import 'dart:math' as math;

import '../models/mse_quote.dart';
import 'fundamentals.dart';

/// Хувьцааны өдөр тутмын түүхээс загварт оруулах шинжүүдийг (features) гаргана.
///
/// Шинж бүрийг тухайн өдөр хүртэлх өгөгдлөөр л тооцно (ирээдүйн мэдээлэл
/// ашиглахгүй). Санхүүгийн үзүүлэлтийг зөвхөн нийтлэгдсэн тайлангаас авна.
class FeatureExtractor {
  /// Шинж тооцоход шаардагдах хамгийн бага арилжааны өдөр.
  static const int lookback = 60;

  /// Нэг өдрийн үнийн өөрчлөлт үүнээс их бол хувьцаа хуваах (split) зэрэг
  /// өгөгдлийн гажуудал гэж үзнэ (ln(1.5) ≈ 50%).
  static const double anomalyLogReturn = 0.405;

  static const List<String> names = [
    'ret5', // 5 арилжааны өдрийн өгөөж
    'ret20', // 20 өдрийн өгөөж
    'ret60', // 60 өдрийн өгөөж
    'vol20', // 20 өдрийн хэлбэлзэл (өдрийн log өгөөжийн std)
    'vol60', // 60 өдрийн хэлбэлзэл
    'rsi14', // RSI(14) / 100 - 0.5
    'ma20gap', // ханш / MA20 - 1
    'ma60gap', // ханш / MA60 - 1
    'dd60', // 60 өдрийн дээд цэгээс унасан хувь
    'volumeRatio', // ln(5 өдрийн дундаж хэмжээ / 60 өдрийн дундаж)
    'liquidity', // арилжаа хийгдсэн өдрийн нягтрал (0..1)
    'relStrength20', // 20 өдрийн өгөөж − зах зээлийн ижил хугацааны өгөөж
    'relStrength60', // 60 өдрийн өгөөж − зах зээлийн өгөөж
    'logTurnover', // log10(20 өдрийн дундаж арилжааны дүн ₮)
    'earningsYield', // EPS / ханш (P/E-ийн урвуу)
    'bookToPrice', // ln(1 + BVPS / ханш)
    'roe', // өмчийн өгөөж
    'hasFundamentals', // санхүүгийн тайлан байгаа эсэх (0/1)
  ];

  static int indexOf(String name) => names.indexOf(name);

  /// [bars]-ийн [i]-р өдрийн шинжүүд. Хангалттай түүхгүй эсвэл
  /// гажуудалтай бол null.
  static List<double>? compute(
    List<MseDailyBar> bars,
    int i, {
    MarketIndex? market,
    FundamentalsSeries? fundamentals,
  }) {
    if (i < lookback || i >= bars.length) return null;
    double c(int k) => bars[k].close;

    final logRets = <double>[];
    for (var k = i - lookback + 1; k <= i; k++) {
      final r = math.log(c(k) / c(k - 1));
      if (r.abs() > anomalyLogReturn) return null;
      logRets.add(r);
    }

    double ret(int n) => c(i) / c(i - n) - 1;
    double mean(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    double std(List<double> xs) {
      final m = mean(xs);
      return math.sqrt(
          xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / xs.length);
    }

    final closes20 = [for (var k = i - 19; k <= i; k++) c(k)];
    final closes60 = [for (var k = i - 59; k <= i; k++) c(k)];

    // RSI(14) — энгийн дундажаар
    var gain = 0.0, loss = 0.0;
    for (var k = i - 13; k <= i; k++) {
      final d = c(k) - c(k - 1);
      if (d > 0) {
        gain += d;
      } else {
        loss -= d;
      }
    }
    final rsi = gain + loss == 0 ? 50.0 : 100 * gain / (gain + loss);

    final vol5 =
        mean([for (var k = i - 4; k <= i; k++) bars[k].volume.toDouble()]);
    final vol60 =
        mean([for (var k = i - 59; k <= i; k++) bars[k].volume.toDouble()]);

    // 60 арилжааны өдөр хэдэн ажлын өдөрт багтсан бэ (≈ хөрвөх чадвар)
    final spanDays = bars[i].date.difference(bars[i - 59].date).inDays + 1;
    final businessDays = math.max(1.0, spanDays * 5 / 7);
    final liquidity = math.min(1.0, 60 / businessDays);

    final mkt20 = market?.returnBetween(bars[i - 20].date, bars[i].date) ?? 0;
    final mkt60 = market?.returnBetween(bars[i - 60].date, bars[i].date) ?? 0;

    final turnover = averageTurnover(bars, i);

    final f = fundamentals?.at(bars[i].date);
    final price = c(i);
    final ey = f?.eps == null ? 0.0 : (f!.eps! / price).clamp(-0.5, 0.5);
    final bp = f?.bvps == null ? 0.0 : math.log(1 + (f!.bvps! / price).clamp(0, 10));
    final roe = f?.roe == null ? 0.0 : f!.roe!.clamp(-1.0, 1.0);
    final has = f == null || f.isEmpty ? 0.0 : 1.0;

    return [
      ret(5),
      ret(20),
      ret(60),
      std(logRets.sublist(logRets.length - 20)),
      std(logRets),
      rsi / 100 - 0.5,
      c(i) / mean(closes20) - 1,
      c(i) / mean(closes60) - 1,
      c(i) / closes60.reduce(math.max) - 1,
      math.log((vol5 + 1) / (vol60 + 1)),
      liquidity,
      ret(20) - mkt20,
      ret(60) - mkt60,
      math.log(turnover + 1) / math.ln10,
      ey.toDouble(),
      bp.toDouble(),
      roe.toDouble(),
      has,
    ];
  }

  /// Сүүлийн 20 арилжааны өдрийн дундаж арилжааны дүн (₮/өдөр).
  static double averageTurnover(List<MseDailyBar> bars, int i, {int n = 20}) {
    final from = math.max(0, i - n + 1);
    var sum = 0.0;
    for (var k = from; k <= i; k++) {
      sum += bars[k].volume * bars[k].close;
    }
    return sum / (i - from + 1);
  }

  /// Сургалтын шошго: [i]-р өдрөөс [entryLag] арилжааны өдрийн дараа авч,
  /// [horizonDays] хоног барьсны өгөөж. entryLag = 1 бол дохио гарсан өдрийн
  /// хаалтаар биш, дараагийн өдөр авна гэж тооцно (бодит, болгоомжтой).
  /// Ирээдүйн өдөр олдохгүй эсвэл гажуудалтай бол null.
  static double? forwardReturn(List<MseDailyBar> bars, int i,
      {int horizonDays = 30, int entryLag = 0}) {
    final s = i + entryLag;
    if (s >= bars.length) return null;
    final target = bars[s].date.add(Duration(days: horizonDays));
    for (var j = i + 1; j < bars.length; j++) {
      final r = math.log(bars[j].close / bars[j - 1].close);
      if (r.abs() > anomalyLogReturn) return null;
      if (j > s && !bars[j].date.isBefore(target)) {
        return bars[j].close / bars[s].close - 1;
      }
    }
    return null;
  }
}

/// Тэнцүү жинтэй зах зээлийн индекс: өдөр бүр арилжаалагдсан хувьцаануудын
/// дундаж өгөөжөөр хуримтлуулсан түвшин.
class MarketIndex {
  final List<DateTime> _dates;
  final List<double> _levels;

  MarketIndex._(this._dates, this._levels);

  factory MarketIndex.fromHistories(Iterable<List<MseDailyBar>> histories) {
    final sums = <DateTime, double>{};
    final counts = <DateTime, int>{};
    for (final bars in histories) {
      for (var k = 1; k < bars.length; k++) {
        final r = math.log(bars[k].close / bars[k - 1].close);
        if (r.abs() > FeatureExtractor.anomalyLogReturn) continue;
        sums[bars[k].date] = (sums[bars[k].date] ?? 0) + r;
        counts[bars[k].date] = (counts[bars[k].date] ?? 0) + 1;
      }
    }
    final dates = sums.keys.toList()..sort();
    final levels = <double>[];
    var logLevel = 0.0;
    for (final d in dates) {
      if (counts[d]! >= 3) logLevel += sums[d]! / counts[d]!;
      levels.add(math.exp(logLevel));
    }
    return MarketIndex._(dates, levels);
  }

  /// [d] өдөр эсвэл түүнээс өмнөх хамгийн ойрын түвшин.
  double? levelAt(DateTime d) {
    var lo = 0, hi = _dates.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (!_dates[mid].isAfter(d)) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans < 0 ? null : _levels[ans];
  }

  double? returnBetween(DateTime from, DateTime to) {
    final a = levelAt(from), b = levelAt(to);
    if (a == null || b == null || a <= 0) return null;
    return b / a - 1;
  }
}

import 'dart:math' as math;

import '../models/mse_quote.dart';

/// Хувьцааны өдөр тутмын түүхээс загварт оруулах шинжүүдийг (features) гаргана.
///
/// Шинж бүрийг тухайн өдөр хүртэлх өгөгдлөөр л тооцно (ирээдүйн мэдээлэл
/// ашиглахгүй), тиймээс сургалт болон апп дотор яг адилхан ажиллана.
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
  ];

  /// [bars]-ийн [i]-р өдрийн шинжүүд. Хангалттай түүхгүй эсвэл
  /// гажуудалтай бол null.
  static List<double>? compute(List<MseDailyBar> bars, int i) {
    if (i < lookback || i >= bars.length) return null;
    final c = (int k) => bars[k].close;

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
      return math.sqrt(xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) /
          xs.length);
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

    final vol5 = mean([for (var k = i - 4; k <= i; k++) bars[k].volume.toDouble()]);
    final vol60 = mean([for (var k = i - 59; k <= i; k++) bars[k].volume.toDouble()]);

    // 60 арилжааны өдөр хэдэн ажлын өдөрт багтсан бэ (≈ хөрвөх чадвар)
    final spanDays = bars[i].date.difference(bars[i - 59].date).inDays + 1;
    final businessDays = math.max(1.0, spanDays * 5 / 7);
    final liquidity = math.min(1.0, 60 / businessDays);

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
    ];
  }

  /// Сургалтын шошго: [i]-р өдрөөс [horizonDays] хоногийн дараах өгөөж.
  /// Ирээдүйн өдөр олдохгүй эсвэл гажуудалтай бол null.
  static double? forwardReturn(List<MseDailyBar> bars, int i,
      {int horizonDays = 30}) {
    final target = bars[i].date.add(Duration(days: horizonDays));
    for (var j = i + 1; j < bars.length; j++) {
      final r = math.log(bars[j].close / bars[j - 1].close);
      if (r.abs() > anomalyLogReturn) return null;
      if (!bars[j].date.isBefore(target)) {
        return bars[j].close / bars[i].close - 1;
      }
    }
    return null;
  }
}

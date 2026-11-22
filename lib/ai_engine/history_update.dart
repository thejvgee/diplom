import '../models/mse_quote.dart';

/// Өдөр тутмын шинэчлэлийн үр дүн.
enum HistoryUpdate {
  /// Шинэ арилжааны өдөр нэмэгдсэн.
  appended,

  /// Шинэ арилжаа алга (амралтын өдөр, арилжаа хийгдээгүй, аль хэдийн нэмсэн).
  unchanged,

  /// Түүх тасарсан (хэд хэдэн өдөр алгассан г.м.) — бүтэн түүхийг дахин татах.
  needsFullRefresh,
}

/// Хувьцааны 4MB түүхийг өдөр бүр бүтнээр нь татахгүйн тулд хамгийн сүүлийн
/// ханшийн мэдээллээс (~5KB) өнөөдрийн арилжааны өдрийг үүсгэж залгана.
class HistoryUpdater {
  /// Сүүлийн хадгалсан өдрийн хаалт ба ханшийн "өмнөх хаалт" яг тэнцүү биш
  /// бол дунд нь өдөр алгассан гэж үзнэ (жижиг ч гэсэн зөрүү = алдсан өдөр).
  static const double maxPrevCloseGap = 1e-6;

  /// Хамгийн сүүлд ДУУССАН арилжааны өдөр (Улаанбаатарын цагаар).
  /// Арилжаа ~13:00-д хаагддаг тул 13:30-аас өмнө бол өмнөх ажлын өдөр
  /// (дуусаагүй арилжааг түүхэнд оруулахгүй). Амралтын өдөр бол баасан.
  static DateTime sessionDate(DateTime nowUtc) {
    final ub = nowUtc.toUtc().add(const Duration(hours: 8));
    var d = DateTime(ub.year, ub.month, ub.day);
    if (ub.hour * 60 + ub.minute < 13 * 60 + 30) {
      d = d.subtract(const Duration(days: 1));
    }
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  /// [bars]-д [quote]-оос шинэ өдөр нэмэх эсэхийг шийдээд нэмнэ.
  static HistoryUpdate apply(
    List<MseDailyBar> bars,
    MseQuote quote,
    DateTime session,
  ) {
    if (quote.volume <= 0 || quote.last <= 0) return HistoryUpdate.unchanged;
    if (bars.isEmpty) return HistoryUpdate.needsFullRefresh;

    final last = bars.last;
    final sameAsLast = quote.last == last.close &&
        quote.open == last.open &&
        quote.volume == last.volume;
    if (sameAsLast || !session.isAfter(last.date)) {
      return HistoryUpdate.unchanged;
    }

    // Өмнөх хаалт таарахгүй бол дунд нь өдөр алгассан байна.
    if (quote.previousClose > 0 &&
        (quote.previousClose - last.close).abs() / last.close >
            maxPrevCloseGap) {
      return HistoryUpdate.needsFullRefresh;
    }

    bars.add(MseDailyBar(
      date: session,
      open: quote.open > 0 ? quote.open : quote.last,
      close: quote.last,
      high: quote.dayHigh > 0 ? quote.dayHigh : quote.last,
      low: quote.dayLow > 0 ? quote.dayLow : quote.last,
      volume: quote.volume,
    ));
    return HistoryUpdate.appended;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/ai_engine/history_update.dart';
import 'package:jvgee_diplom/models/mse_quote.dart';

MseDailyBar _bar(DateTime d, double close, {double open = 100, int volume = 10}) =>
    MseDailyBar(date: d, open: open, close: close, high: close, low: close, volume: volume);

MseQuote _quote({
  double prev = 100,
  double open = 101,
  double last = 102,
  int volume = 500,
}) =>
    MseQuote(
      symbol: 'APU',
      previousClose: prev,
      open: open,
      last: last,
      vwap: last,
      bidPrice: 0,
      bidQty: 0,
      askPrice: 0,
      askQty: 0,
      dayLow: 100,
      dayHigh: 103,
      volume: volume,
      turnover: 0,
      trades: 1,
      week52Low: 0,
      week52High: 0,
      isin: '',
      marketCap: 0,
      fetchedAt: DateTime(2026, 11, 16),
    );

void main() {
  group('sessionDate', () {
    test('арилжаа дууссаны дараа өнөөдөр', () {
      // Даваа 14:00 УБ = 06:00 UTC
      expect(HistoryUpdater.sessionDate(DateTime.utc(2026, 11, 16, 6)),
          DateTime(2026, 11, 16));
    });
    test('арилжаа дуусахаас өмнө өмнөх ажлын өдөр', () {
      // Даваа 11:00 УБ → баасан
      expect(HistoryUpdater.sessionDate(DateTime.utc(2026, 11, 16, 3)),
          DateTime(2026, 11, 13));
    });
    test('амралтын өдөр баасан', () {
      expect(HistoryUpdater.sessionDate(DateTime.utc(2026, 11, 15, 8)),
          DateTime(2026, 11, 13));
    });
  });

  group('apply', () {
    final fri = DateTime(2026, 11, 13);
    final mon = DateTime(2026, 11, 16);

    test('шинэ арилжааны өдрийг залгана', () {
      final bars = [_bar(fri, 100)];
      expect(HistoryUpdater.apply(bars, _quote(), mon), HistoryUpdate.appended);
      expect(bars.length, 2);
      expect(bars.last.date, mon);
      expect(bars.last.close, 102);
      expect(bars.last.high, 103);
    });

    test('аль хэдийн нэмсэн бол давхардуулахгүй', () {
      final bars = [_bar(fri, 100), _bar(mon, 102, open: 101, volume: 500)];
      expect(HistoryUpdater.apply(bars, _quote(), mon), HistoryUpdate.unchanged);
      expect(bars.length, 2);
    });

    test('арилжаа хийгдээгүй бол өөрчлөхгүй', () {
      final bars = [_bar(fri, 100)];
      expect(HistoryUpdater.apply(bars, _quote(volume: 0), mon),
          HistoryUpdate.unchanged);
    });

    test('өдөр алгассан (өмнөх хаалт таарахгүй) бол бүтэн татна', () {
      final bars = [_bar(fri, 90)];
      expect(HistoryUpdater.apply(bars, _quote(prev: 100), mon),
          HistoryUpdate.needsFullRefresh);
      expect(bars.length, 1);
    });

    test('жижиг зөрүүтэй ч өдөр алгассан гэж үзнэ (APU 1100 → 1095)', () {
      final bars = [_bar(fri, 1100)];
      expect(HistoryUpdater.apply(bars, _quote(prev: 1095, open: 1096, last: 1094), mon),
          HistoryUpdate.needsFullRefresh);
    });

    test('хоосон түүх бол бүтэн татна', () {
      expect(HistoryUpdater.apply([], _quote(), mon),
          HistoryUpdate.needsFullRefresh);
    });
  });
}

// Шалгах скрипт: dart run tool/mse_probe.dart
import 'package:jvgee_diplom/services/mse_service.dart';

Future<void> main() async {
  final svc = MseService();
  final sw = Stopwatch()..start();
  final list = await svc.fetchSecurities();
  final byCat = <int, int>{};
  for (final s in list) {
    byCat[s.category] = (byCat[s.category] ?? 0) + 1;
  }
  print('securities: ${list.length} $byCat (${sw.elapsedMilliseconds}ms)');
  for (final sym in ['APU', 'KHAN', 'TTL', 'MSE']) {
    final sec = list.firstWhere((s) => s.symbol == sym);
    sw.reset();
    final q = await svc.fetchQuote(sec);
    print('${q.symbol} id=${sec.id} last=${q.last} prev=${q.previousClose} '
        'chg=${q.change.toStringAsFixed(2)} (${q.changePercent.toStringAsFixed(2)}%) '
        'bid=${q.bidPrice}x${q.bidQty} ask=${q.askPrice}x${q.askQty} '
        'day=${q.dayLow}-${q.dayHigh} vol=${q.volume} 52w=${q.week52Low}-${q.week52High} '
        'isin=${q.isin} (${sw.elapsedMilliseconds}ms)');
  }
  sw.reset();
  final apu = list.firstWhere((s) => s.symbol == 'APU');
  final hist = await svc.fetchHistory(apu);
  print('APU history: ${hist.length} bars, last=${hist.last.date} close=${hist.last.close} (${sw.elapsedMilliseconds}ms)');
  print('marketOpen now: ${MseService.isMarketOpen()}');
}

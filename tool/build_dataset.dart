// MSE-ийн I, II ангиллын хувьцааны өдөр тутмын түүхийг
// tool/data/history/<SYMBOL>.json-д хадгалж, шинэчилнэ.
//
//   dart run tool/build_dataset.dart            # өдөр тутмын шинэчлэл
//   dart run tool/build_dataset.dart --refresh  # бүгдийг бүтнээр нь дахин татна
//
// Өдөр тутмын горимд хувьцаа бүрийн сүүлийн ханшийг (~5KB) л татаж
// өнөөдрийн өдрийг түүхэнд залгана. Бүтэн түүх (~4MB/хувьцаа) зөвхөн
// шинэ хувьцаа, тасарсан түүх, эсвэл --refresh үед татагдана.
import 'dart:convert';
import 'dart:io';

import 'package:jvgee_diplom/ai_engine/history_update.dart';
import 'package:jvgee_diplom/models/mse_quote.dart';
import 'package:jvgee_diplom/services/mse_service.dart';

Future<void> main(List<String> args) async {
  final refresh = args.contains('--refresh');
  final outDir = Directory('tool/data/history')..createSync(recursive: true);
  final svc = MseService();
  final session = HistoryUpdater.sessionDate(DateTime.now().toUtc());

  final securities =
      (await svc.fetchSecurities()).where((s) => s.category <= 2).toList();
  File('tool/data/securities.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ')
        .convert(securities.map((s) => s.toJson()).toList()),
  );
  stdout.writeln('${securities.length} хувьцаа (I, II ангилал), '
      'арилжааны өдөр ${_d(session)}${refresh ? ', бүтэн шинэчлэл' : ''}');

  final counts = <String, int>{};
  var failures = 0;
  for (var i = 0; i < securities.length; i++) {
    final sec = securities[i];
    final file = File('${outDir.path}/${sec.symbol}.json');
    final tag = '[${i + 1}/${securities.length}] ${sec.symbol}';
    try {
      final quote = await svc.fetchQuote(sec);
      var bars = refresh || !file.existsSync() ? null : _read(file);
      var result = 'өөрчлөлтгүй';
      var update =
          bars == null ? HistoryUpdate.needsFullRefresh : HistoryUpdater.apply(bars, quote, session);
      if (update == HistoryUpdate.needsFullRefresh) {
        // Сайтын түүх ~1 өдрөөр хоцордог тул бүтэн татсны дараа өнөөдрийн
        // өдрийг ханшаас дахин залгана.
        bars = await svc.fetchHistory(sec);
        result = 'бүтэн татсан';
        update = HistoryUpdater.apply(bars, quote, session);
        _write(file, bars);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } else if (update == HistoryUpdate.appended) {
        _write(file, bars!);
        result = 'нэмэгдсэн';
      }
      counts[result] = (counts[result] ?? 0) + 1;
      stdout.writeln('$tag: $result'
          '${update == HistoryUpdate.appended && result != 'нэмэгдсэн' ? ' + өнөөдөр' : ''}'
          ' (сүүлийн өдөр ${bars!.isEmpty ? '—' : _d(bars.last.date)})');
    } catch (e) {
      failures++;
      stderr.writeln('$tag: АЛДАА $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  stdout.writeln('Дүн: $counts, алдаа: $failures');

  // Санхүүгийн тайлан: долоо хоногт нэг удаа (эсвэл --refresh) шинэчилнэ.
  final fundDir = Directory('tool/data/fundamentals')..createSync(recursive: true);
  var fundUpdated = 0, fundFailed = 0;
  for (final sec in securities) {
    final f = File('${fundDir.path}/${sec.symbol}.json');
    final fresh = f.existsSync() &&
        DateTime.now().difference(f.lastModifiedSync()) < const Duration(days: 7);
    if (fresh && !refresh) continue;
    try {
      final reports = await svc.fetchFundamentals(sec);
      f.writeAsStringSync(jsonEncode([for (final r in reports) r.toJson()]));
      fundUpdated++;
    } catch (e) {
      fundFailed++;
      stderr.writeln('${sec.symbol}: санхүүгийн тайлан АЛДАА $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  stdout.writeln('Санхүүгийн тайлан: $fundUpdated шинэчилсэн, $fundFailed алдаа');
  // Ихэнх нь амжилтгүй бол (сайт унасан г.м.) хуучин дохиог дарж бичихгүй.
  if (failures > securities.length ~/ 4) exit(1);
}

List<MseDailyBar> _read(File f) => [
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
    ].fold<Map<String, MseDailyBar>>({}, (m, b) => m..[_d(b.date)] = b).values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

void _write(File f, List<MseDailyBar> bars) => f.writeAsStringSync(jsonEncode([
      for (final b in bars)
        [_d(b.date), b.open, b.high, b.low, b.close, b.volume],
    ]));

String _d(DateTime d) => d.toIso8601String().substring(0, 10);

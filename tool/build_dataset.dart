// MSE-ийн I, II ангиллын хувьцааны өдөр тутмын түүхийг татаж
// tool/data/history/<SYMBOL>.json болгон хадгална.
//
//   dart run tool/build_dataset.dart            # дутуу байгааг л татна
//   dart run tool/build_dataset.dart --refresh  # бүгдийг шинээр татна
//
// Хувьцаа бүрийн хуудас ~4MB тул сайтад ачаалал өгөхгүйн тулд
// дараалан, завсарлагатай татна.
import 'dart:convert';
import 'dart:io';

import 'package:jvgee_diplom/services/mse_service.dart';

Future<void> main(List<String> args) async {
  final refresh = args.contains('--refresh');
  final outDir = Directory('tool/data/history')..createSync(recursive: true);
  final svc = MseService();

  final securities =
      (await svc.fetchSecurities()).where((s) => s.category <= 2).toList();
  File('tool/data/securities.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ')
        .convert(securities.map((s) => s.toJson()).toList()),
  );
  stdout.writeln('${securities.length} хувьцаа (I, II ангилал)');

  var done = 0;
  for (final sec in securities) {
    final file = File('${outDir.path}/${sec.symbol}.json');
    done++;
    if (!refresh && file.existsSync()) continue;
    try {
      final bars = await svc.fetchHistory(sec);
      file.writeAsStringSync(jsonEncode([
        for (final b in bars)
          [
            b.date.toIso8601String().substring(0, 10),
            b.open,
            b.high,
            b.low,
            b.close,
            b.volume,
          ],
      ]));
      stdout.writeln('[$done/${securities.length}] ${sec.symbol}: ${bars.length} өдөр');
    } catch (e) {
      stderr.writeln('[$done/${securities.length}] ${sec.symbol}: АЛДАА $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

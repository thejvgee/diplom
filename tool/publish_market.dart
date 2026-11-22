// Вэб хувилбарт зориулж MSE-ийн ханшийг JSON болгон бэлдэнэ.
//
//   dart run tool/publish_market.dart [--out build/mse] [--history tool/data/history]
//
// open.mse.mn нь CORS header өгдөггүй тул browser тэр сайтаас шууд уншиж
// чадахгүй. GitHub Actions (.github/workflows/refresh-signals.yml) энэ
// скриптийг өдөр бүр ажиллуулж, гаралтыг Firebase Hosting-ийн /mse/ дор
// байршуулна. Вэб апп нь lib/services/mse_snapshot_service.dart-аар уншина.
//
// Гаралт:
//   <out>/market.json            I–III ангиллын жагсаалт + сүүлийн ханш
//   <out>/history/<SYMBOL>.json  сүүлийн ~1 жилийн түүх (tool/data/history-оос;
//                                эхлээд dart run tool/build_dataset.dart)
import 'dart:convert';
import 'dart:io';

import 'package:jvgee_diplom/models/mse_quote.dart';
import 'package:jvgee_diplom/services/mse_service.dart';
import 'package:jvgee_diplom/services/mse_snapshot_service.dart';

/// Апп-ын график сүүлийн 3 сарыг (эсвэл хамгийн багадаа 60 өдрийг) харуулдаг.
const _historyDays = 400;
const _minBars = 60;
const _concurrency = 4;

Future<void> main(List<String> args) async {
  String arg(String name, String fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final out = Directory(arg('--out', 'build/mse'));
  final historyDir = Directory(arg('--history', 'tool/data/history'));

  final svc = MseService();
  final securities = await svc.fetchSecurities();
  stdout.writeln('${securities.length} хувьцаа (I–III ангилал)');

  final quotes = <String, MseQuote>{};
  final failures = <String>[];
  for (var i = 0; i < securities.length; i += _concurrency) {
    await Future.wait(
      securities.skip(i).take(_concurrency).map((s) async {
        try {
          quotes[s.symbol] = await svc.fetchQuote(s);
        } catch (e) {
          failures.add(s.symbol);
          stderr.writeln('${s.symbol}: АЛДАА $e');
        }
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  stdout.writeln('Ханш: ${quotes.length} амжилттай, ${failures.length} алдаа');
  // Сайт унасан г.м. үед хагас дутуу өгөгдөл нийтлэхгүй (хуучин нь үлдэнэ).
  if (failures.length > securities.length ~/ 4) {
    stderr.writeln('Хэт олон алдаа — нийтлэхгүй.');
    exit(1);
  }

  if (out.existsSync()) out.deleteSync(recursive: true);
  final outHistory = Directory('${out.path}/history')
    ..createSync(recursive: true);

  final withHistory = <String>{};
  if (!historyDir.existsSync()) {
    stderr.writeln('${historyDir.path} алга — график нийтлэхгүй '
        '(эхлээд dart run tool/build_dataset.dart).');
  } else {
    final cutoff = DateTime.now().subtract(const Duration(days: _historyDays));
    for (final s in securities) {
      final f = File('${historyDir.path}/${s.symbol}.json');
      if (!f.existsSync()) continue;
      final bars = _readBars(f);
      if (bars.length < 2) continue;
      var recent = bars.where((b) => !b.date.isBefore(cutoff)).toList();
      if (recent.length < _minBars) {
        recent = bars.sublist(bars.length > _minBars ? bars.length - _minBars : 0);
      }
      File('${outHistory.path}/${s.symbol}.json')
          .writeAsStringSync(jsonEncode([for (final b in recent) b.toRow()]));
      withHistory.add(s.symbol);
    }
  }

  final snapshot = MseSnapshot(
    generatedAt: DateTime.now().toUtc(),
    securities: securities,
    quotes: quotes,
    historySymbols: withHistory,
  );
  File('${out.path}/market.json').writeAsStringSync(jsonEncode(snapshot.toJson()));
  stdout.writeln('${out.path}/market.json бичигдлээ; '
      'түүх: ${withHistory.length} хувьцаа');
}

List<MseDailyBar> _readBars(File f) {
  final byDate = <String, MseDailyBar>{};
  for (final r in jsonDecode(f.readAsStringSync()) as List) {
    final row = r as List;
    final date = row[0] as String;
    // Сайтын өгөгдөлд "0000-00-00" гэх мэт буруу огноо байдаг.
    if (date.startsWith('-') || date.startsWith('0')) continue;
    try {
      byDate[date] = MseDailyBar.fromRow(row);
    } on FormatException {
      continue;
    }
  }
  return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}

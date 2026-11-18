// Firebase Hosting-д байршуулах хавтсыг бүрдүүлнэ:
//
//   <out>/       ← вэб апп       (flutter build web → build/web)
//   <out>/ai/    ← AI дохио      (assets/ai, docs/ai_model_report.md,
//                                 tool/data/signal_log.json)
//   <out>/mse/   ← MSE-ийн ханш  (dart run tool/publish_market.dart → build/mse)
//
//   dart run tool/assemble_hosting.dart [--web build/web] [--mse build/mse] [--out build/hosting]
//
// Firebase Hosting нь deploy бүрт сайтыг БҮХЭЛД нь солидог. Тиймээс энэ
// гурвыг заавал хамт байршуулна — эс бөгөөс вэб апп, дохио эсвэл ханш
// сайтаас алга болно. Дутуу бол алдаа өгч зогсоно.
import 'dart:io';

void main(List<String> args) {
  String arg(String name, String fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final web = Directory(arg('--web', 'build/web'));
  final mse = Directory(arg('--mse', 'build/mse'));
  final out = Directory(arg('--out', 'build/hosting'));

  final required = {
    '${web.path}/index.html': 'flutter build web --release',
    '${web.path}/main.dart.js': 'flutter build web --release',
    '${mse.path}/market.json': 'dart run tool/publish_market.dart',
    'assets/ai/signals.json': 'dart run tool/train_advisor.dart',
    'assets/ai/advisor_model.json': 'dart run tool/train_advisor.dart',
  };
  final missing = [
    for (final e in required.entries)
      if (!File(e.key).existsSync()) '${e.key}  (← ${e.value})',
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('Дутуу файл:\n  ${missing.join('\n  ')}');
    exit(1);
  }

  if (out.existsSync()) out.deleteSync(recursive: true);
  _copyDir(web, out);
  _copyDir(mse, Directory('${out.path}/mse'));

  final ai = Directory('${out.path}/ai')..createSync(recursive: true);
  File('assets/ai/signals.json').copySync('${ai.path}/signals.json');
  File('assets/ai/advisor_model.json').copySync('${ai.path}/advisor_model.json');
  for (final (src, name) in [
    ('docs/ai_model_report.md', 'report.md'),
    ('tool/data/signal_log.json', 'signal_log.json'),
  ]) {
    final f = File(src);
    if (f.existsSync()) {
      f.copySync('${ai.path}/$name');
    } else {
      // signal_log.json-ийг workflow нь нийтлэгдсэнээс сэргээдэг.
      stderr.writeln('Анхаар: $src алга — ai/$name нийтлэгдэхгүй.');
    }
  }

  final files = out.listSync(recursive: true).whereType<File>().length;
  stdout.writeln('${out.path}: $files файл бэлэн (firebase deploy --only hosting)');
}

void _copyDir(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: true)) {
    final rel = entity.path.substring(from.path.length + 1);
    if (entity is Directory) {
      Directory('${to.path}/$rel').createSync(recursive: true);
    } else if (entity is File) {
      File('${to.path}/$rel').parent.createSync(recursive: true);
      entity.copySync('${to.path}/$rel');
    }
  }
}

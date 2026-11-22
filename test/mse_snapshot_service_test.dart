import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jvgee_diplom/firebase_init.dart';
import 'package:jvgee_diplom/models/mse_quote.dart';
import 'package:jvgee_diplom/providers/mse_market_provider.dart';
import 'package:jvgee_diplom/services/mse_service.dart';
import 'package:jvgee_diplom/services/mse_snapshot_service.dart';

const _apu = MseSecurity(id: 90, symbol: 'APU', name: 'АПУ ХК', category: 1);
const _khan = MseSecurity(id: 563, symbol: 'KHAN', name: 'Хаан банк ХК', category: 1);
const _mgla = MseSecurity(id: 38, symbol: 'MGLA', name: 'Эм Жи Эл Акуа ХК', category: 3);

MseQuote _quote(String symbol, double last) => MseQuote(
  symbol: symbol,
  previousClose: 1100,
  open: 1100,
  last: last,
  vwap: 1098.92,
  bidPrice: 1095,
  bidQty: 1111,
  askPrice: 1096,
  askQty: 14112,
  dayLow: 1095,
  dayHigh: 1100,
  volume: 26505,
  turnover: 29126897,
  trades: 222,
  week52Low: 912,
  week52High: 1132,
  isin: 'MN00APU00900',
  marketCap: 1165278800535,
  fetchedAt: DateTime.utc(2026, 11, 18, 5, 50),
);

String _marketJson() => jsonEncode(
  MseSnapshot(
    generatedAt: DateTime.utc(2026, 11, 18, 5, 52),
    securities: const [_apu, _khan, _mgla],
    quotes: {'APU': _quote('APU', 1095), 'KHAN': _quote('KHAN', 990)},
    historySymbols: {'APU'},
  ).toJson(),
);

/// Хүсэлтүүдийг тоолдог хуурамч сервер.
class _Server {
  final requests = <String>[];
  String market = _marketJson();
  int marketStatus = 200;

  http.Client client() => MockClient((req) async {
    requests.add(req.url.path);
    if (req.url.path.endsWith('/market.json')) {
      return http.Response.bytes(utf8.encode(market), marketStatus);
    }
    if (req.url.path.endsWith('/history/APU.json')) {
      return http.Response(
        jsonEncode([
          ['2026-11-18', 1100, 1100, 1095, 1095, 26505],
          ['2026-11-17', 1090, 1101, 1088, 1100, 1000],
        ]),
        200,
      );
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('MseQuote / MseDailyBar JSON', () {
    test('MseQuote toJson → fromJson утгаа хадгална', () {
      final q = _quote('APU', 1095);
      final back = MseQuote.fromJson(
        jsonDecode(jsonEncode(q.toJson())) as Map<String, dynamic>,
      );
      expect(back.symbol, 'APU');
      expect(back.last, 1095);
      expect(back.bidQty, 1111);
      expect(back.marketCap, 1165278800535);
      expect(back.isin, 'MN00APU00900');
      expect(back.fetchedAt.toUtc(), DateTime.utc(2026, 11, 18, 5, 50));
      expect(back.changePercent, closeTo(q.changePercent, 1e-9));
    });

    test('MseDailyBar нягт мөр рүү хөрвөнө', () {
      final bar = MseDailyBar(
        date: DateTime(2026, 11, 18),
        open: 1100,
        high: 1101,
        low: 1095,
        close: 1095,
        volume: 26505,
      );
      expect(bar.toRow(), ['2026-11-18', 1100.0, 1101.0, 1095.0, 1095.0, 26505]);
      final back = MseDailyBar.fromRow(jsonDecode(jsonEncode(bar.toRow())) as List);
      expect(back.date, DateTime(2026, 11, 18));
      expect(back.close, 1095);
      expect(back.volume, 26505);
    });
  });

  group('MseSnapshotService', () {
    late _Server server;
    late DateTime now;
    late MseSnapshotService svc;

    setUp(() {
      server = _Server();
      now = DateTime(2026, 11, 18, 14);
      svc = MseSnapshotService(
        dataUrl: 'https://example.test/mse/',
        clientFactory: server.client,
        now: () => now,
      );
    });

    test('жагсаалт ба ханшийг нэг л татлаар өгнө', () async {
      final list = await svc.fetchSecurities();
      expect(list.map((s) => s.symbol), ['APU', 'KHAN', 'MGLA']);
      expect(list.last.category, 3);
      final quotes = await Future.wait([svc.fetchQuote(_apu), svc.fetchQuote(_khan)]);
      expect(quotes.map((q) => q.last), [1095, 990]);
      expect(server.requests, ['/mse/market.json']);
      expect(svc.generatedAt!.toUtc(), DateTime.utc(2026, 11, 18, 5, 52));
    });

    test('зэрэг ирсэн хүсэлтүүд нэг татал хуваалцана', () async {
      await Future.wait([svc.fetchQuote(_apu), svc.fetchQuote(_khan), svc.fetchSecurities()]);
      expect(server.requests, ['/mse/market.json']);
    });

    test('maxAge өнгөрвөл дахин татна', () async {
      await svc.fetchQuote(_apu);
      now = now.add(const Duration(minutes: 2));
      await svc.fetchQuote(_apu);
      expect(server.requests, ['/mse/market.json', '/mse/market.json']);
    });

    test('ханш нийтлэгдээгүй хувьцаа алдаа өгнө', () async {
      expect(() => svc.fetchQuote(_mgla), throwsA(isA<MseException>()));
    });

    test('түүхийг history/<SYMBOL>.json-оос эрэмбэлж уншина', () async {
      final bars = await svc.fetchHistory(_apu);
      expect(bars.map((b) => b.date.day), [17, 18]);
      expect(bars.last.close, 1095);
      // Түүх нийтлэгдээгүй хувьцаанд хүсэлт явуулахгүй
      expect(await svc.fetchHistory(_mgla), isEmpty);
      expect(server.requests, ['/mse/market.json', '/mse/history/APU.json']);
    });

    test('HTTP алдаа MseException болно', () async {
      server.marketStatus = 404;
      expect(svc.fetchSecurities, throwsA(isA<MseException>()));
    });

    test('танихгүй хувилбартай файлыг хүлээж авахгүй', () async {
      server.market = jsonEncode({'version': 99});
      expect(svc.fetchSecurities, throwsA(isA<MseException>()));
    });
  });

  test('MseMarketProvider snapshot-оос ханш, хугацааг авна', () async {
    final server = _Server();
    final provider = MseMarketProvider(
      service: MseSnapshotService(
        dataUrl: 'https://example.test/mse',
        clientFactory: server.client,
      ),
      openInterval: null,
    );
    await provider.refresh(reloadList: true);
    expect(provider.isSnapshot, isTrue);
    expect(provider.error, isNull);
    expect(provider.visibleSecurities.map((s) => s.symbol), ['APU', 'KHAN']);
    expect(provider.lastPrices, {'APU': 1095, 'KHAN': 990});
    expect(provider.snapshotTime!.toUtc(), DateTime.utc(2026, 11, 18, 5, 52));
    expect(await provider.historyFor('APU'), hasLength(2));
    provider.dispose();
  });

  group('FirebaseWebConfig', () {
    test('init.json-оос тохиргоо уншина', () {
      final o = FirebaseWebConfig.fromInitJson({
        'apiKey': 'test-key',
        'appId': '1:1:web:1',
        'projectId': 'demo-project',
        'storageBucket': 'demo-project.firebasestorage.app',
        'authDomain': 'demo-project.firebaseapp.com',
        'messagingSenderId': '1',
      });
      expect(o.apiKey, 'test-key');
      expect(o.projectId, 'demo-project');
      expect(o.authDomain, 'demo-project.firebaseapp.com');
      expect(o.storageBucket, 'demo-project.firebasestorage.app');
    });

    test('дутуу init.json-ийг хүлээж авахгүй', () {
      expect(
        () => FirebaseWebConfig.fromInitJson({'projectId': 'x'}),
        throwsFormatException,
      );
    });

    test('init.json-д appId байхгүй бол анхдагч вэб appId-г ашиглана', () {
      // Console дээр вэб апп hosting сайттай холбогдоогүй үед ингэж ирдэг
      final o = FirebaseWebConfig.fromInitJson(
          {'apiKey': 'k', 'projectId': 'diplom-23056', 'authDomain': 'd'});
      expect(o.appId, FirebaseWebConfig.appId);
    });

    test('сайтын /__/firebase/init.json-оос татна', () async {
      Uri? asked;
      final o = await FirebaseWebConfig.load(
        base: Uri.parse('https://demo-project.web.app/#/home'),
        fetcher: (url) async {
          asked = url;
          return jsonEncode({'apiKey': 'k', 'appId': 'a', 'projectId': 'p'});
        },
      );
      expect(asked.toString(), 'https://demo-project.web.app/__/firebase/init.json');
      expect(o.authDomain, 'p.firebaseapp.com');
    });

    test('тохиргоо олдохгүй бол ойлгомжтой алдаа өгнө', () async {
      expect(
        FirebaseWebConfig.load(
          base: Uri.parse('http://localhost:5000/'),
          fetcher: (_) async => throw Exception('HTTP 404'),
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('web_config.json'))),
      );
    });
  });
}

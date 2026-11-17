import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/ai_engine/signals.dart';
import 'package:jvgee_diplom/providers/advisor_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _signalsJson(DateTime generatedAt, {DateTime? date, int count = 1}) =>
    jsonEncode(SignalSet(
      generatedAt: generatedAt,
      signals: [
        for (var i = 0; i < count; i++)
          StockSignal(
            symbol: 'S$i',
            name: 'S$i ХК',
            category: 1,
            date: date ?? generatedAt,
            price: 100,
            probUp: 0.5,
            dailyVol: 0.02,
            ret20: 0,
            ret60: 0,
            drawdown60: 0,
            liquidity: 1,
            rsi: 50,
          ),
      ],
      modelMetrics: {'baseRateUp': 0.46},
    ).toJson());

Future<void> _settle(AdvisorProvider p) async {
  for (var i = 0; i < 100 && (p.isLoading || p.isRefreshing); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('серверийн шинэ дохиог хэрэглэж, утсанд кэшлэнэ', () async {
    final future = DateTime.now().add(const Duration(days: 1));
    final p = AdvisorProvider(
      remoteUrl: 'https://example.test/signals.json',
      fetcher: (_) async => _signalsJson(future, date: DateTime.now(), count: 3),
    );
    await p.load();
    await _settle(p);
    expect(p.source, SignalsSource.remote);
    expect(p.signals!.signals.length, 3);
    expect(p.isStale, isFalse);

    // Дараагийн нээлтэд интернэтгүй байсан ч кэшээс ачаална
    final offline = AdvisorProvider(
      remoteUrl: 'https://example.test/signals.json',
      fetcher: (_) async => throw Exception('offline'),
    );
    await offline.load();
    await _settle(offline);
    expect(offline.source, SignalsSource.cache);
    expect(offline.signals!.signals.length, 3);
    expect(offline.remoteError, isNotNull);
  });

  test('серверийнх хуучин эсвэл эвдэрсэн бол апп доторхоороо үлдэнэ', () async {
    final old = AdvisorProvider(
      remoteUrl: 'https://example.test/signals.json',
      fetcher: (_) async => _signalsJson(DateTime(2020)),
    );
    await old.load();
    await _settle(old);
    expect(old.source, SignalsSource.bundled);

    final broken = AdvisorProvider(
      remoteUrl: 'https://example.test/signals.json',
      fetcher: (_) async => '{"signals": []',
    );
    await broken.load();
    await _settle(broken);
    expect(broken.source, SignalsSource.bundled);
    expect(broken.remoteError, isNotNull);
  });

  test('цагт нэгээс олон удаа серверт хандахгүй', () async {
    var calls = 0;
    final p = AdvisorProvider(
      remoteUrl: 'https://example.test/signals.json',
      fetcher: (_) async {
        calls++;
        return _signalsJson(DateTime(2020));
      },
    );
    await p.load();
    await _settle(p);
    await p.refreshRemote();
    await p.refreshRemote();
    expect(calls, 1);
    await p.refreshRemote(force: true);
    expect(calls, 2);
  });
}

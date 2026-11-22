import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/ai_engine/advisor_engine.dart';
import 'package:jvgee_diplom/ai_engine/chat_context.dart';
import 'package:jvgee_diplom/ai_engine/risk_profile.dart';
import 'package:jvgee_diplom/ai_engine/signals.dart';
import 'package:jvgee_diplom/providers/mse_market_provider.dart';

void main() {
  final signals = SignalSet.fromJson(jsonDecode(
          File('assets/ai/signals.json').readAsStringSync())
      as Map<String, dynamic>);

  group('parseAmountMnt', () {
    test('янз бүрийн бичлэг', () {
      expect(ChatContext.parseAmountMnt("Надад 100'000'000 төгрөг байна"), 1e8);
      expect(ChatContext.parseAmountMnt('100,000,000₮'), 1e8);
      expect(ChatContext.parseAmountMnt('10 сая төгрөг'), 1e7);
      expect(ChatContext.parseAmountMnt('1.5 сая'), 1.5e6);
      expect(ChatContext.parseAmountMnt('500 мянга'), 5e5);
      expect(ChatContext.parseAmountMnt('2 тэрбум'), 2e9);
      expect(ChatContext.parseAmountMnt('тоо алга'), isNull);
    });
  });

  group('investAmount', () {
    test('дүнтэй хөрөнгө оруулалтын асуулт', () {
      expect(
          ChatContext.investAmount(
              "Надад 100'000'000 төгрөг байна, би ямар хөрөнгө оруулалтын багц бүрдүүлэх ёстой вэ?"),
          1e8);
      expect(ChatContext.investAmount('5 сая төгрөгөө юунд оруулах вэ'), 5e6);
    });
    test('нас эсвэл дүнгүй асуултыг Gemini-д үлдээнэ', () {
      expect(
          ChatContext.investAmount(
              '35 настай хүнд хамгийн оновчтой хөрөнгийн оруулалтын багц юу вэ?'),
          isNull);
      expect(ChatContext.investAmount('Төсвөө хэрхэн бүрдүүлэх вэ?'), isNull);
    });
  });

  test('investmentPlan нь бодит дохиогоор хуваарилалт гаргана', () {
    final text = ChatContext.investmentPlan(
      engine: AdvisorEngine(signals),
      amount: 1e8,
      profile: RiskProfile.fromKey('Moderate'),
    );
    expect(text, contains('100,000,000₮'));
    expect(text, contains('ширхэг'));
    expect(text, contains(ChatContext.localTag));
    // Санал болгосон бүх хувьцаа дохионы жагсаалтад байгаа (зохиомол биш)
    final symbols = RegExp(r'\*\*([A-Z]+)\*\*').allMatches(text).map((m) => m.group(1));
    expect(symbols, isNotEmpty);
    for (final s in symbols) {
      expect(signals.signalFor(s!), isNotNull, reason: '$s дохионд байх ёстой');
    }
  });

  test('build контекст нь багц, дохио, дүрмийг агуулна', () {
    final text = ChatContext.build(
      signals: signals,
      report: null,
      holdings: [HoldingInput(symbol: 'APU', quantity: 10, averageCost: 1000)],
      cash: 5e6,
      profile: RiskProfile.fromKey('Conservative'),
      livePrices: {'APU': 1100},
    );
    expect(text, contains('[АПП-ЫН БОДИТ ӨГӨГДӨЛ]'));
    expect(text, contains('Консерватив'));
    expect(text, contains('APU: 10 ширхэг'));
    expect(text, contains('+10.0%'));
    expect(text, contains('ДҮРЭМ'));
  });

  test('шинэчлэх давтамжийн тохиргоо', () {
    expect(MseMarketProvider.parseRefreshInterval('5 минут'),
        const Duration(minutes: 5));
    expect(MseMarketProvider.parseRefreshInterval('Гараар'), isNull);
    // хуучин англи утга → анхдагч
    expect(MseMarketProvider.parseRefreshInterval('15 minutes'),
        const Duration(minutes: 1));
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/providers/advisor_provider.dart';
import 'package:jvgee_diplom/providers/mse_market_provider.dart';
import 'package:jvgee_diplom/providers/portfolio_provider.dart';
import 'package:jvgee_diplom/providers/user_preferences_provider.dart';
import 'package:jvgee_diplom/screen/portfolio_suggestions_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'portfolio_provider_test.dart' show FakeRemote;

void main() {
  testWidgets('AI зөвлөх өөрийн загвараар багцын шинжилгээ гаргана',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = StreamController<String?>();
    final portfolio = PortfolioProvider(remote: FakeRemote(), userIds: auth.stream);
    auth.add('u1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          // remoteUrl хоосон → тестэд сүлжээнд хандахгүй
          ChangeNotifierProvider(create: (_) => AdvisorProvider(remoteUrl: '')),
          ChangeNotifierProvider.value(value: portfolio),
          ChangeNotifierProvider(create: (_) => UserPreferencesProvider()),
          // start() дуудахгүй тул сүлжээнд хандахгүй
          ChangeNotifierProvider(create: (_) => MseMarketProvider()),
        ],
        child: MaterialApp(home: PortfolioSuggestionsScreen()),
      ),
    );
    // assets/ai/signals.json ачаалагдах хүртэл
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Санал болгох багц боловсруулах'), findsOneWidget);
    expect(find.textContaining('Тест AUC'), findsOneWidget);

    await tester.ensureVisible(find.text('Санал болгох багц боловсруулах'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Санал болгох багц боловсруулах'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.text('Багцын эрүүл мэнд'), findsOneWidget);
    expect(find.text('Зорилтот хуваарилалт'), findsOneWidget);
    // Зөвлөгөөнүүд жагсаалтын доор байрлана
    await tester.scrollUntilVisible(
      find.textContaining('ширхэг авах'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('ширхэг авах'), findsWidgets);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/models/transaction.dart';
import 'package:jvgee_diplom/providers/portfolio_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firestore-ийн оронд санах ойд хадгалдаг хуурамч сервер.
class FakeRemote implements PortfolioRemoteStore {
  final Map<String, Map<String, dynamic>> docs = {};
  @override
  Future<Map<String, dynamic>?> load(String uid) async => docs[uid];
  @override
  Future<void> save(String uid, Map<String, dynamic> data) async =>
      docs[uid] = Map.of(data);
  @override
  Future<void> delete(String uid) async => docs.remove(uid);
}

Future<PortfolioProvider> _open(
  StreamController<String?> auth,
  FakeRemote remote,
  String? uid,
) async {
  final p = PortfolioProvider(remote: remote, userIds: auth.stream);
  auth.add(uid);
  await _settle(p);
  return p;
}

Future<void> _settle(PortfolioProvider p) async {
  for (var i = 0; i < 50 && p.isLoading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('шинэ хэрэглэгч 10 сая төгрөгтэй, хоосон багцаар эхэлнэ', () async {
    final p = await _open(StreamController<String?>(), FakeRemote(), 'u1');
    expect(p.cashBalance, PortfolioProvider.initialCash);
    expect(p.holdings, isEmpty);
  });

  test('авсан хувьцаа апп дахин нээхэд хадгалагдсан байна', () async {
    final remote = FakeRemote();
    final p1 = await _open(StreamController<String?>(), remote, 'u1');
    expect(await p1.buyStock('APU', 100, 1000), isTrue);
    p1.dispose();

    final p2 = await _open(StreamController<String?>(), remote, 'u1');
    expect(p2.holdings.single.symbol, 'APU');
    expect(p2.holdings.single.quantity, 100);
    expect(p2.cashBalance, PortfolioProvider.initialCash - 100000);
    expect(p2.transactions.single.action, 'buy');
  });

  test('утасны кэш устсан ч серверээс сэргээнэ', () async {
    final remote = FakeRemote();
    final p1 = await _open(StreamController<String?>(), remote, 'u1');
    await p1.buyStock('KHAN', 10, 2000);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    SharedPreferences.setMockInitialValues({}); // шинэ утас

    final p2 = await _open(StreamController<String?>(), remote, 'u1');
    expect(p2.holdings.single.symbol, 'KHAN');
  });

  test('хэрэглэгч бүрийн багц тусдаа', () async {
    final auth = StreamController<String?>();
    final p = await _open(auth, FakeRemote(), 'alice');
    await p.buyStock('TTL', 5, 58000);

    auth.add('bob');
    await _settle(p);
    expect(p.holdings, isEmpty);
    expect(p.cashBalance, PortfolioProvider.initialCash);

    auth.add('alice');
    await _settle(p);
    expect(p.holdings.single.symbol, 'TTL');
  });

  test('байхгүй хувьцаа зарах, мөнгөнөөс их авах боломжгүй', () async {
    final p = await _open(StreamController<String?>(), FakeRemote(), 'u1');
    expect(await p.sellStock('APU', 1, 1000), isFalse);
    expect(await p.buyStock('APU', 1e6, 1000), isFalse);
    expect(await p.buyStock('APU', 10, 1000), isTrue);
    expect(await p.sellStock('APU', 11, 1000), isFalse);
    expect(await p.sellStock('APU', 10, 1100), isTrue);
    expect(p.holdings, isEmpty);
    expect(p.cashBalance, PortfolioProvider.initialCash + 1000);
  });

  test('өнөөдрийн өөрчлөлтийг бодит өмнөх хаалтаар тооцно', () async {
    final p = await _open(StreamController<String?>(), FakeRemote(), 'u1');
    expect(p.dayChange, isNull);
    await p.buyStock('APU', 100, 1000);
    p.updateLivePrices({'APU': 1050}, previousCloses: {'APU': 1020});
    expect(p.dayChange, closeTo(100 * 30, 1e-9));
    expect(p.holdings.single.currentPrice, 1050);
    expect(p.valueHistory, isNotEmpty);
    expect(p.changeSince(7), isNull); // 7 хоногийн түүх хараахан алга
  });

  test('шинэчлэн эхлүүлэх ба бүх өгөгдлийг устгах', () async {
    final remote = FakeRemote();
    final p = await _open(StreamController<String?>(), remote, 'u1');
    await p.buyStock('APU', 10, 1000);
    await p.resetPortfolio();
    expect(p.holdings, isEmpty);
    expect(p.cashBalance, PortfolioProvider.initialCash);

    await p.deleteAllData();
    expect(remote.docs.containsKey('u1'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('portfolio_v2_u1'), isNull);
  });

  test('Transaction.fromJson бүхэл тоог (Firestore) зөв уншина', () {
    final t = Transaction.fromJson({
      'symbol': 'APU',
      'action': 'buy',
      'quantity': 10,
      'price': 1000,
      'totalAmount': 10000,
      'timestamp': '2026-11-15T10:00:00.000',
    });
    expect(t.quantity, 10.0);
    expect(t.price, 1000.0);
  });
}

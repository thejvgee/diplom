import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/services/mse_service.dart';

// open.mse.mn-ийн бодит HTML-ийн богиносгосон хувилбарууд (2026-11).
const _securitiesHtml = '''
<div class="tab-pane active" id="class1" role="tabpanel">
<table class="table table-striped table-sm">
<tr><th>№</th><th>Симбол</th><th>Компанийн нэр</th></tr>
<tr><td>1</td><td><a href="https://open.mse.mn/securities/90">APU</a></td>
<td><a href="https://open.mse.mn/securities/90">АПУ ХК</a></td></tr>
<tr><td>2</td><td><a href="https://open.mse.mn/securities/563">KHAN</a></td>
<td><a href="https://open.mse.mn/securities/563">Хаан банк ХК</a></td></tr>
</table></div>
<div class="tab-pane" id="class2" role="tabpanel">
<table class="table table-striped table-sm">
<tr><td>1</td><td><a href="https://open.mse.mn/securities/38">MGLA</a></td>
<td><a href="https://open.mse.mn/securities/38">Эм Жи Эл Акуа ХК</a></td></tr>
</table></div>
<div class="tab-pane" id="delisted" role="tabpanel">
<table><tr><td>1</td><td><a href="https://open.mse.mn/securities/5">OLD</a></td>
<td><a href="https://open.mse.mn/securities/5">Хасагдсан ХК</a></td></tr></table></div>
''';

const _tradeHtml = '''
<table class="table table-striped table-sm">
<tr> <td>Өмнөх өдрийн хаалтын ханш</td> <td><strong>1,100.00</strong></td> </tr>
<tr> <td>Нээлтийн ханш</td> <td><strong>1,100.00</strong></td> </tr>
<tr> <td>Хаалтын ханш</td> <td><strong>1,095.00</strong></td> </tr>
<tr> <td>Тухайн өдрийн VWAP</td> <td><strong>1,098.92</strong></td> </tr>
<tr> <td>Авах дээд үнэ</td> <td><strong>1,095.00 x 1,111</strong></td> </tr>
<tr> <td>Зарах доод үнэ</td> <td><strong>1,096.00 x 14,112</strong></td> </tr>
</table>
<table class="table table-striped table-sm">
<tr> <td>Өдрийн хязгаар</td> <td><strong>1,095.00 - 1,100.00</strong></td> </tr>
<tr> <td>Арилжигдсан ширхэг</td> <td><strong>26,505</strong></td> </tr>
<tr> <td>Арилжааны үнийн дүн</td> <td><strong>29,126,897.00</strong></td> </tr>
<tr> <td>Хэлцлийн тоо</td> <td><strong>222</strong></td> </tr>
<tr> <td>52 долоо хоног</td> <td><strong>912.00 - 1,132.00</strong></td> </tr>
<tr> <td>ISIN</td> <td><strong>MN00APU00900</strong></td> </tr>
<tr> <td>Зах зээлийн үнэлгээ</td> <td><strong> 1,165,278,800,535.00 </strong></td> </tr>
</table>
<div id="chartcontrols"></div>
<div id="chart-data" data-trading-histories='[{"OpeningPrice":1100,"ClosingPrice":1100,"HighPrice":1108,"LowPrice":1095,"Volume":46184,"dates":"2026-11-12"},{"OpeningPrice":1120,"ClosingPrice":1123,"HighPrice":1125,"LowPrice":1110,"Volume":1000,"dates":"2026-11-11"},{"OpeningPrice":0,"ClosingPrice":0,"Volume":0,"dates":"2026-11-10"}]'></div>
''';

void main() {
  test('parseSecurities нь I–III ангиллыг уншиж, хасагдсаныг алгасна', () {
    final list = MseService.parseSecurities(_securitiesHtml);
    expect(list.map((s) => s.symbol), ['APU', 'KHAN', 'MGLA']);
    expect(list.first.id, 90);
    expect(list.first.name, 'АПУ ХК');
    expect(list.first.category, 1);
    expect(list.last.category, 2);
  });

  test('parseQuote нь ханш, өөрчлөлт, захиалгын мэдээллийг уншина', () {
    final q = MseService.parseQuote('APU', _tradeHtml);
    expect(q.previousClose, 1100);
    expect(q.last, 1095);
    expect(q.price, 1095);
    expect(q.change, -5);
    expect(q.changePercent, closeTo(-0.4545, 0.001));
    expect(q.bidPrice, 1095);
    expect(q.bidQty, 1111);
    expect(q.askPrice, 1096);
    expect(q.askQty, 14112);
    expect(q.dayLow, 1095);
    expect(q.dayHigh, 1100);
    expect(q.volume, 26505);
    expect(q.trades, 222);
    expect(q.week52High, 1132);
    expect(q.isin, 'MN00APU00900');
    expect(q.marketCap, 1165278800535);
  });

  test('parseQuote ханшгүй хуудсанд алдаа шиднэ', () {
    expect(() => MseService.parseQuote('X', '<html></html>'),
        throwsA(isA<MseException>()));
  });

  test('parseHistory нь огноогоор эрэмбэлж, 0 ханштайг хасна', () {
    final bars = MseService.parseHistory(_tradeHtml);
    expect(bars.length, 2);
    expect(bars.first.date, DateTime(2026, 11, 11));
    expect(bars.last.close, 1100);
  });

  test('isMarketOpen нь УБ-ын цагаар ажлын өдрийн 10–13 цагийг таньна', () {
    // 2026-11-13 Баасан, УБ 11:00 = UTC 03:00
    expect(MseService.isMarketOpen(DateTime.utc(2026, 11, 13, 3)), isTrue);
    // УБ 15:00
    expect(MseService.isMarketOpen(DateTime.utc(2026, 11, 13, 7)), isFalse);
    // 2026-11-15 Ням
    expect(MseService.isMarketOpen(DateTime.utc(2026, 11, 15, 3)), isFalse);
  });
}

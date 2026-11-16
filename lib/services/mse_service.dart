import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/mse_quote.dart';

/// Монголын хөрөнгийн биржийн (MSE) нээлттэй мэдээллийн сайт
/// https://open.mse.mn-ээс үнэгүйгээр арилжааны мэдээлэл татна.
///
/// MSE-д албан ёсны нээлттэй API байхгүй тул нийтэд нээлттэй HTML
/// хуудсуудыг уншиж задлана. open.mse.mn-ийн robots.txt бүх замыг
/// зөвшөөрдөг. (mse.mn/api-г robots.txt хаасан тул ашиглахгүй.)
///
/// Хувьцаа бүрийн "tradeinfo" хуудас ~4MB (12+ жилийн түүхтэй) тул
/// ханш авахдаа зөвхөн эхний хэдэн KB-ийг уншаад холболтыг таслана.
class MseService {
  static const String baseUrl = 'https://open.mse.mn';
  static const Duration _timeout = Duration(seconds: 20);
  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (jvgee_diplom MSE viewer)',
    'Accept': 'text/html',
  };

  /// Ханшийн хүснэгтийн араас гарч ирдэг тэмдэг. Үүнийг хүлээн авмагц
  /// үлдсэн (том) түүхийн хэсгийг татахгүй.
  static const String _quoteEndMarker = 'id="chartcontrols"';
  static const int _quoteMaxBytes = 64 * 1024;

  final http.Client Function() _clientFactory;

  MseService({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  // ---------------------------------------------------------------------------
  // Үнэт цаасны жагсаалт
  // ---------------------------------------------------------------------------

  /// I, II, III ангиллын бүх хувьцааны жагсаалт.
  Future<List<MseSecurity>> fetchSecurities() async {
    final client = _clientFactory();
    try {
      final res = await client
          .get(Uri.parse('$baseUrl/securities'), headers: _headers)
          .timeout(_timeout);
      if (res.statusCode != 200) {
        throw MseException('Жагсаалт татахад алдаа: HTTP ${res.statusCode}');
      }
      return parseSecurities(utf8.decode(res.bodyBytes, allowMalformed: true));
    } finally {
      client.close();
    }
  }

  static final RegExp _securityRow = RegExp(
    r'<a href="https://open\.mse\.mn/securities/(\d+)">\s*([^<]+?)\s*</a>\s*</td>\s*'
    r'<td>\s*<a href="https://open\.mse\.mn/securities/\1">\s*([^<]+?)\s*</a>',
  );

  static List<MseSecurity> parseSecurities(String html) {
    final result = <MseSecurity>[];
    final seen = <String>{};
    for (var category = 1; category <= 3; category++) {
      final start = html.indexOf('id="class$category"');
      if (start < 0) continue;
      final tableEnd = html.indexOf('</table>', start);
      final section = html.substring(
        start,
        tableEnd < 0 ? html.length : tableEnd,
      );
      for (final m in _securityRow.allMatches(section)) {
        final symbol = _decodeEntities(m.group(2)!).trim();
        if (!seen.add(symbol)) continue;
        result.add(
          MseSecurity(
            id: int.parse(m.group(1)!),
            symbol: symbol,
            name: _decodeEntities(m.group(3)!).trim(),
            category: category,
          ),
        );
      }
    }
    if (result.isEmpty) {
      throw MseException(
        'open.mse.mn хуудасны бүтэц өөрчлөгдсөн байж магадгүй',
      );
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Ханш (сүүлийн арилжааны мэдээлэл)
  // ---------------------------------------------------------------------------

  /// Нэг хувьцааны хамгийн сүүлийн ханш. Зөвхөн хуудасны эхний хэсгийг уншина.
  Future<MseQuote> fetchQuote(MseSecurity security) async {
    final client = _clientFactory();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/securities/${security.id}/tab/tradeinfo'),
      )..headers.addAll(_headers);
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        throw MseException('${security.symbol}: HTTP ${response.statusCode}');
      }

      final bytes = <int>[];
      String text = '';
      await for (final chunk in response.stream.timeout(_timeout)) {
        bytes.addAll(chunk);
        text = utf8.decode(bytes, allowMalformed: true);
        if (text.contains(_quoteEndMarker) || bytes.length >= _quoteMaxBytes) {
          break; // Үлдсэн 4MB түүхийг татахгүй.
        }
      }
      return parseQuote(security.symbol, text);
    } finally {
      client.close();
    }
  }

  static final RegExp _labelValue = RegExp(
    r'<td>\s*([^<]+?)\s*</td>\s*<td>\s*<strong>\s*([^<]*?)\s*</strong>',
  );

  static MseQuote parseQuote(String symbol, String html) {
    final fields = <String, String>{};
    for (final m in _labelValue.allMatches(html)) {
      fields.putIfAbsent(m.group(1)!.trim(), () => m.group(2)!.trim());
    }
    if (!fields.containsKey('Хаалтын ханш')) {
      throw MseException('$symbol: ханшийн мэдээлэл олдсонгүй');
    }

    final bid = _parsePriceQty(fields['Авах дээд үнэ']);
    final ask = _parsePriceQty(fields['Зарах доод үнэ']);
    final dayRange = _parseRange(fields['Өдрийн хязгаар']);
    final weekRange = _parseRange(fields['52 долоо хоног']);

    return MseQuote(
      symbol: symbol,
      previousClose: _num(fields['Өмнөх өдрийн хаалтын ханш']),
      open: _num(fields['Нээлтийн ханш']),
      last: _num(fields['Хаалтын ханш']),
      vwap: _num(fields['Тухайн өдрийн VWAP']),
      bidPrice: bid.$1,
      bidQty: bid.$2,
      askPrice: ask.$1,
      askQty: ask.$2,
      dayLow: dayRange.$1,
      dayHigh: dayRange.$2,
      volume: _num(fields['Арилжигдсан ширхэг']).round(),
      turnover: _num(fields['Арилжааны үнийн дүн']),
      trades: _num(fields['Хэлцлийн тоо']).round(),
      week52Low: weekRange.$1,
      week52High: weekRange.$2,
      isin: fields['ISIN'] ?? '',
      marketCap: _num(fields['Зах зээлийн үнэлгээ']),
      fetchedAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // Түүх (график)
  // ---------------------------------------------------------------------------

  /// Хувьцааны өдөр тутмын арилжааны түүх. Бүтэн хуудсыг (~4MB) татдаг тул
  /// зөвхөн хэрэглэгч дэлгэрэнгүйг нээх үед дуудна.
  Future<List<MseDailyBar>> fetchHistory(MseSecurity security) async {
    final client = _clientFactory();
    try {
      final res = await client
          .get(
            Uri.parse('$baseUrl/securities/${security.id}/tab/tradeinfo'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        throw MseException('${security.symbol}: HTTP ${res.statusCode}');
      }
      return parseHistory(utf8.decode(res.bodyBytes, allowMalformed: true));
    } finally {
      client.close();
    }
  }

  static final RegExp _historyAttr = RegExp(
    r"data-trading-histories='([\s\S]*?)'",
  );

  static List<MseDailyBar> parseHistory(String html) {
    final m = _historyAttr.firstMatch(html);
    if (m == null) return [];
    final list = jsonDecode(_decodeEntities(m.group(1)!)) as List<dynamic>;
    final bars = <MseDailyBar>[];
    for (final item in list) {
      final row = item as Map<String, dynamic>;
      final date = DateTime.tryParse('${row['dates']}');
      final close = (row['ClosingPrice'] as num?)?.toDouble() ?? 0;
      // Зарим мөрөнд "0000-00-00" гэх мэт буруу огноо байдаг.
      if (date == null || date.year < 2000 || close <= 0) continue;
      bars.add(
        MseDailyBar(
          date: date,
          open: (row['OpeningPrice'] as num?)?.toDouble() ?? close,
          close: close,
          high: (row['HighPrice'] as num?)?.toDouble() ?? close,
          low: (row['LowPrice'] as num?)?.toDouble() ?? close,
          volume: (row['Volume'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    // Сайтын өгөгдөлд ижил өдөр давхардсан мөр байдаг — нэг өдөрт нэг мөр үлдээнэ.
    final byDate = <DateTime, MseDailyBar>{for (final b in bars) b.date: b};
    return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  // ---------------------------------------------------------------------------
  // Туслах функцууд
  // ---------------------------------------------------------------------------

  /// MSE-ийн арилжааны цаг: Даваа–Баасан, Улаанбаатарын цагаар (UTC+8)
  /// ойролцоогоор 10:00–13:00. Бага зэрэг өргөн хүрээ авав.
  static bool isMarketOpen([DateTime? now]) {
    final ub = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    if (ub.weekday == DateTime.saturday || ub.weekday == DateTime.sunday) {
      return false;
    }
    final minutes = ub.hour * 60 + ub.minute;
    return minutes >= 9 * 60 + 30 && minutes <= 13 * 60 + 30;
  }

  static double _num(String? s) {
    if (s == null) return 0;
    final cleaned = s.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  /// "1,095.00 x 1,111" -> (1095.0, 1111)
  static (double, int) _parsePriceQty(String? s) {
    if (s == null) return (0, 0);
    final parts = s.split('x');
    return (_num(parts.first), parts.length > 1 ? _num(parts[1]).round() : 0);
  }

  /// "1,095.00 - 1,100.00" -> (1095.0, 1100.0)
  static (double, double) _parseRange(String? s) {
    if (s == null) return (0, 0);
    final parts = s.split(' - ');
    if (parts.length != 2) return (0, 0);
    return (_num(parts[0]), _num(parts[1]));
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

class MseException implements Exception {
  final String message;
  MseException(this.message);
  @override
  String toString() => message;
}

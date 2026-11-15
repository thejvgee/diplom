import 'dart:convert';

import 'package:http/http.dart' as http;

/// Криптовалютын бодит ханш (Binance-ийн нээлттэй market-data API) болон
/// ам.доллар → төгрөгийн ханш (open.er-api.com). Хоёулаа үнэгүй, түлхүүргүй.
class CryptoService {
  static const String _binance = 'https://data-api.binance.vision/api/v3';
  static const String _fx = 'https://open.er-api.com/v6/latest/USD';
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client Function() _clientFactory;
  CryptoService({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  Future<List<CryptoQuote>> fetchQuotes(Map<String, String> assets) async {
    final pairs = assets.keys.map((s) => '"${s}USDT"').join(',');
    final body = await _get('$_binance/ticker/24hr?symbols=${Uri.encodeComponent('[$pairs]')}');
    return parseQuotes(body, assets);
  }

  /// Сүүлийн [limit] цагийн хаалтын үнэ (USD).
  Future<List<double>> fetchHourlyCloses(String symbol, {int limit = 48}) async {
    final body = await _get('$_binance/klines?symbol=${symbol}USDT&interval=1h&limit=$limit');
    return [
      for (final k in jsonDecode(body) as List) double.parse((k as List)[4] as String)
    ];
  }

  /// 1 ам.доллар хэдэн төгрөг вэ.
  Future<double> fetchUsdMnt() async {
    final json = jsonDecode(await _get(_fx)) as Map<String, dynamic>;
    final rate = ((json['rates'] as Map?)?['MNT'] as num?)?.toDouble();
    if (json['result'] != 'success' || rate == null || rate <= 0) {
      throw Exception('Валютын ханш олдсонгүй');
    }
    return rate;
  }

  static List<CryptoQuote> parseQuotes(String body, Map<String, String> assets) {
    final list = jsonDecode(body) as List;
    return [
      for (final item in list)
        () {
          final m = item as Map<String, dynamic>;
          final symbol = (m['symbol'] as String).replaceAll('USDT', '');
          return CryptoQuote(
            symbol: symbol,
            name: assets[symbol] ?? symbol,
            priceUsd: double.parse(m['lastPrice'] as String),
            changePercent: double.parse(m['priceChangePercent'] as String),
            highUsd: double.parse(m['highPrice'] as String),
            lowUsd: double.parse(m['lowPrice'] as String),
            volume: double.parse(m['volume'] as String),
          );
        }(),
    ];
  }

  Future<String> _get(String url) async {
    final client = _clientFactory();
    try {
      final res = await client.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      return utf8.decode(res.bodyBytes);
    } finally {
      client.close();
    }
  }
}

class CryptoQuote {
  final String symbol;
  final String name;
  final double priceUsd;
  final double changePercent; // 24 цагийн
  final double highUsd;
  final double lowUsd;
  final double volume;

  const CryptoQuote({
    required this.symbol,
    required this.name,
    required this.priceUsd,
    required this.changePercent,
    required this.highUsd,
    required this.lowUsd,
    required this.volume,
  });
}

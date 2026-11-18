/// Монголын хөрөнгийн биржийн (MSE) өгөгдлийн загварууд.
/// Эх сурвалж: https://open.mse.mn (нээлттэй, robots.txt-ээр зөвшөөрөгдсөн).

/// Биржид бүртгэлтэй нэг үнэт цаас (хувьцаа).
class MseSecurity {
  /// open.mse.mn дээрх компанийн дугаар (жишээ: APU = 90).
  final int id;
  final String symbol;
  final String name;

  /// Ангилал: 1 = I ангилал, 2 = II ангилал, 3 = III ангилал.
  final int category;

  const MseSecurity({
    required this.id,
    required this.symbol,
    required this.name,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'symbol': symbol,
    'name': name,
    'category': category,
  };

  factory MseSecurity.fromJson(Map<String, dynamic> json) => MseSecurity(
    id: json['id'] as int,
    symbol: json['symbol'] as String,
    name: json['name'] as String,
    category: json['category'] as int,
  );
}

/// Тухайн хувьцааны хамгийн сүүлийн арилжааны мэдээлэл.
class MseQuote {
  final String symbol;
  final double previousClose;
  final double open;

  /// Хаалтын / хамгийн сүүлийн ханш.
  final double last;
  final double vwap;
  final double bidPrice;
  final int bidQty;
  final double askPrice;
  final int askQty;
  final double dayLow;
  final double dayHigh;
  final int volume;
  final double turnover;
  final int trades;
  final double week52Low;
  final double week52High;
  final String isin;
  final double marketCap;

  /// Апп өгөгдлийг татсан цаг.
  final DateTime fetchedAt;

  const MseQuote({
    required this.symbol,
    required this.previousClose,
    required this.open,
    required this.last,
    required this.vwap,
    required this.bidPrice,
    required this.bidQty,
    required this.askPrice,
    required this.askQty,
    required this.dayLow,
    required this.dayHigh,
    required this.volume,
    required this.turnover,
    required this.trades,
    required this.week52Low,
    required this.week52High,
    required this.isin,
    required this.marketCap,
    required this.fetchedAt,
  });

  /// Арилжаа хийгдээгүй үед хаалтын ханш 0 байж болох тул
  /// өмнөх хаалтын ханшийг ашиглана.
  double get price => last > 0 ? last : previousClose;

  /// Өмнөх өдрийн хаалтаас хэдэн төгрөгөөр өөрчлөгдсөн.
  double get change => previousClose > 0 && last > 0 ? last - previousClose : 0;

  /// Өмнөх өдрийн хаалтаас хэдэн хувиар өөрчлөгдсөн.
  double get changePercent =>
      previousClose > 0 && last > 0 ? (change / previousClose) * 100 : 0;

  bool get tradedToday => volume > 0;

  /// Вэб хувилбарт нийтлэх (`tool/publish_market.dart` → `mse/market.json`).
  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'previousClose': previousClose,
    'open': open,
    'last': last,
    'vwap': vwap,
    'bidPrice': bidPrice,
    'bidQty': bidQty,
    'askPrice': askPrice,
    'askQty': askQty,
    'dayLow': dayLow,
    'dayHigh': dayHigh,
    'volume': volume,
    'turnover': turnover,
    'trades': trades,
    'week52Low': week52Low,
    'week52High': week52High,
    'isin': isin,
    'marketCap': marketCap,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
  };

  factory MseQuote.fromJson(Map<String, dynamic> json) {
    double d(String k) => (json[k] as num?)?.toDouble() ?? 0;
    int i(String k) => (json[k] as num?)?.toInt() ?? 0;
    return MseQuote(
      symbol: json['symbol'] as String,
      previousClose: d('previousClose'),
      open: d('open'),
      last: d('last'),
      vwap: d('vwap'),
      bidPrice: d('bidPrice'),
      bidQty: i('bidQty'),
      askPrice: d('askPrice'),
      askQty: i('askQty'),
      dayLow: d('dayLow'),
      dayHigh: d('dayHigh'),
      volume: i('volume'),
      turnover: d('turnover'),
      trades: i('trades'),
      week52Low: d('week52Low'),
      week52High: d('week52High'),
      isin: json['isin'] as String? ?? '',
      marketCap: d('marketCap'),
      fetchedAt:
          DateTime.tryParse('${json['fetchedAt']}')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// Нэг өдрийн арилжааны түүх (график зурахад).
class MseDailyBar {
  final DateTime date;
  final double open;
  final double close;
  final double high;
  final double low;
  final int volume;

  const MseDailyBar({
    required this.date,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    required this.volume,
  });

  /// Нягт хэлбэр `[огноо, open, high, low, close, volume]` — `tool/data/history`
  /// болон вэбд нийтэлдэг `mse/history/<SYMBOL>.json` энэ хэлбэртэй.
  List<Object> toRow() => [
    date.toIso8601String().substring(0, 10),
    open,
    high,
    low,
    close,
    volume,
  ];

  factory MseDailyBar.fromRow(List<dynamic> row) => MseDailyBar(
    date: DateTime.parse(row[0] as String),
    open: (row[1] as num).toDouble(),
    high: (row[2] as num).toDouble(),
    low: (row[3] as num).toDouble(),
    close: (row[4] as num).toDouble(),
    volume: (row[5] as num).toInt(),
  );
}

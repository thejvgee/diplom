import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class MarketDataService {
  final storage = FlutterSecureStorage();
  Timer? _refreshTimer;
  final StreamController<Map<String, dynamic>> _dataStreamController = StreamController.broadcast();
  WebSocketChannel? _webSocketChannel;
  bool _hasError = false;
  Map<String, dynamic> _lastSuccessfulData = {};

  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;

  Future<void> initialize() async {
    try {
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(Duration(seconds: 30), (_) async {
        _refreshMarketData();
      });
      await _refreshMarketData();
      await subscribeToSymbol('btcusdt');
      _hasError = false;
    } catch (e) {
      _hasError = true;
      print('Failed to initialize market data service: $e');
      rethrow;
    }
  }

  Future<void> _refreshMarketData() async {
    try {
      final mockData = _createMockMarketData();
      _dataStreamController.add(mockData);
      _lastSuccessfulData = mockData;
      print('Market data refreshed: ${mockData.keys.toList()}');
    } catch (e) {
      print('Error fetching market data: $e');
      if (_lastSuccessfulData.isNotEmpty) {
        _lastSuccessfulData['isCached'] = true;
        _lastSuccessfulData['cacheTime'] = DateTime.now().millisecondsSinceEpoch;
        _dataStreamController.add(_lastSuccessfulData);
        print('Using cached market data');
      } else {
        final mockData = _createMockMarketData();
        mockData['isMock'] = true;
        _dataStreamController.add(mockData);
        print('Using mock market data');
      }
    }
  }

  Map<String, dynamic> _createMockMarketData() {
    return {
      'stocks': {
        'c': 147.56, // current price
        'h': 148.21, // high price
        'l': 146.08, // low price
        'o': 146.35, // open price
        'pc': 146.18, // previous close
        'dp': 0.95, // percent change
      },
      'time': DateTime.now().millisecondsSinceEpoch,
      'isCached': false,
      'isMock': true
    };
  }

  Future<Map<String, dynamic>> getStockDetails(String symbol) async {
    return {
      'c': 158.4, // current price
      'h': 159.1, // high price
      'l': 157.3, // low price
      'o': 157.5, // open price
      'pc': 158.1, // previous close
      'dp': 0.32, // percent change
      'symbol': symbol,
      'isMock': true
    };
  }

  Future<Map<String, dynamic>> getCryptoDetails(String symbol) async {
    return {
      'c': [19823.45], // close prices
      'h': [20145.67], // high prices
      'l': [19712.33], // low prices
      'o': [19755.88], // open prices
      'v': [1256.78], // volumes
      't': [DateTime.now().millisecondsSinceEpoch ~/ 1000], // timestamps
      's': 'ok', // status
      'symbol': symbol,
      'isMock': true
    };
  }
  Future<Map<String, dynamic>> getMarketData(String symbol, String timeframe, {bool useMockData = false}) async {
    return _getMockDataForTimeframe(symbol, timeframe);
  }
  Map<String, dynamic> _formatCandleData(Map<String, dynamic> data) {
    return {
      'time': data['t'] != null ? (data['t'] as List).map((t) => t * 1000).toList() : [],
      'open': data['o'] ?? [],
      'high': data['h'] ?? [],
      'low': data['l'] ?? [],
      'close': data['c'] ?? [],
      'volume': data['v'] ?? [],
    };
  }
  Future<bool> _checkConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }
  Map<String, dynamic> _getMockDataForTimeframe(String symbol, String timeframe) {
    final now = DateTime.now();
    double basePrice;
    switch (symbol) {
      case 'AARD':
        basePrice = 2450.0;
        break;
      case 'ADB':
        basePrice = 100.0;
        break;
      case 'APU':
        basePrice = 978.0;
        break;
      case 'BODI':
        basePrice = 82.0;
        break;
      default:
        basePrice = 100.0;
    }
    int dataPoints;
    switch (timeframe) {
      case '1D':
        dataPoints = 24 * 4;    // Every 15 minutes
        break;
      case '1W':
        dataPoints = 7 * 8;     // Every 3 hours
        break;
      case '1M':
        dataPoints = 30;        // Daily
        break;
      case '3M':
        dataPoints = 90;        // Daily
        break;
      case '1Y':
        dataPoints = 52;        // Weekly
        break;
      case '5Y':
        dataPoints = 60;        // Monthly
        break;
      default:
        dataPoints = 30;        // Default to daily
    }
    double volatility;
    switch (timeframe) {
      case '1D':
        volatility = 0.003;
        break;
      case '1W':
        volatility = 0.007;
        break;
      case '1M':
        volatility = 0.02;
        break;
      case '3M':
        volatility = 0.05;
        break;
      case '1Y':
        volatility = 0.1;
        break;
      case '5Y':
        volatility = 0.3;
        break;
      default:
        volatility = 0.02;
    }
    int timeInterval;
    switch (timeframe) {
      case '1D':
        timeInterval = Duration(minutes: 15).inMilliseconds;
        break;
      case '1W':
        timeInterval = Duration(hours: 3).inMilliseconds;
        break;
      case '1M':
        timeInterval = Duration(days: 1).inMilliseconds;
        break;
      case '3M':
        timeInterval = Duration(days: 1).inMilliseconds;
        break;
      case '1Y':
        timeInterval = Duration(days: 7).inMilliseconds;
        break;
      case '5Y':
        timeInterval = Duration(days: 30).inMilliseconds;
        break;
      default:
        timeInterval = Duration(days: 1).inMilliseconds;
    }

    final times = List<int>.generate(
        dataPoints,
            (i) => now.subtract(Duration(milliseconds: (dataPoints - 1 - i) * timeInterval)).millisecondsSinceEpoch
    );
    double currentPrice = basePrice;
    final trend = (now.millisecondsSinceEpoch % 2 == 0) ? 1.0 : -1.0;
    final trendStrength = volatility * 10;

    final opens = <double>[];
    final highs = <double>[];
    final lows = <double>[];
    final closes = <double>[];
    final volumes = <double>[];

    for (int i = 0; i < dataPoints; i++) {
      final randomFactor = (i * 17 % 100) / 100.0 - 0.5;
      final trendFactor = trend * trendStrength * (i / dataPoints);
      final dayChange = currentPrice * volatility * randomFactor + currentPrice * trendFactor;

      final open = currentPrice;
      final close = currentPrice + dayChange;
      final high = math.max(open, close) + currentPrice * volatility * 0.5 * ((i * 31) % 100) / 100.0;
      final low = math.min(open, close) - currentPrice * volatility * 0.5 * ((i * 23) % 100) / 100.0;
      final volume = basePrice * 100000 * (0.5 + ((i * 13) % 100) / 50.0);

      opens.add(open);
      highs.add(high);
      lows.add(low);
      closes.add(close);
      volumes.add(volume);

      currentPrice = close;
    }

    return {
      'time': times,
      'open': opens,
      'high': highs,
      'low': lows,
      'close': closes,
      'volume': volumes,
      'isMock': true,
    };
  }

  Future<List<Map<String, dynamic>>> getMarketNews() async {
    return [
      {
        'title': 'Apple шинэ iPhone-оо зарлалаа',
        'summary': 'Apple компани хамгийн сүүлийн үеийн камерын онцлог, батерейны ашиглалтын хугацааг уртасгасан iPhone-оо танилцууллаа.',
        'date': DateTime.now().toString(),
        'url': '',
        'source': 'Market News',
      },
      {
        'title': 'Bitcoin ий үнэ шинэ дээд цэгтээ хүрэв',
        'summary': 'Институциональ хөрөнгө оруулагчид сонирхсоор байгаа тул өнөөдөр биткойн бүх цаг үеийн дээд цэгтээ хүрэв.',
        'date': DateTime.now().toString(),
        'url': '',
        'source': 'Crypto News',
      },
      {
        'title': 'Энэ долоо хоногт хоёрдогч зах зээл дээр 4.4 тэрбум төгрөгийн арилжаа явагджээ',
        'summary': 'Долоо хоногийн сүүлийн арилжааны өдөр МХБирж дээр 1.71 сая гаруй ширхэг үнэт цаас 1.13 тэрбум төгрөгөөр арилжигдснаар нийт 5 өдөрт 4.4 тэрбум төгрөгийн арилжаа явагдав. Мөн 141,300 ам.долларын ногоон бонд зарагджээ. ',
        'date': DateTime.now().toString(),
        'url': '',
        'source': 'Economic News',
      },
      {
        'title': 'Өнөөдөр хөрөнгийн зах зээлийн нийт үнэлгээ +65.4 тэрбум төгрөгөөр өсөв',
        'summary': '[ ХЗЗ-ийн тойм: 2025.05.08] Пүрэв гарагт ТОП-20 индекс эргэн ирэлт хийж, 3 өдрийн алдагдлаа нөхөж чадлаа. Өнөөдөр тус индекс +1.12%-ийн өсөлт үзүүлснээр 49,594.47 нэгжид хаагдсан бол MSE-A индекс +1.00%-ийн, MSE-B индекс +0.12%-ийн өсөлтийг тус тус үзүүллээ. Хувьцааны I самбарт арилжигддаг [MSE:INV] Инвескор ХК (+10.45%), [MSE] Монголын хөрөнгийн бирж ХК (+1.84%), [MSE:MNP] Монгол шуудан ХК (+6.93%)-ийн хувьцааны ханш зах зээлийг өсөлттэй хаагдахад нөлөөлөв.',
        'date': DateTime.now().toString(),
        'url': '',
        'source': 'Market News',
      },
      {
        'title': 'ТОП-20 индекс долоо хоногийн эхний 3 өдөр нийт -1.30%-иар унаад байна',
        'summary': 'Энэ долоо талдаа орж байхад ТОП-20 индекс 3 дараалсан бууралтыг үзүүлээд байгаа ба өнөөдөр -0.86%-иар, нийт 3 өдөрт -1.30%-иар унаад байна. Өнөөдрийн хувьд [MSE:APU] АПУ ХК (-0.64%), [MSE:GOV] Говь ХК (-1.44%), [MSE:SUU] Сүү ХК (-1.25%), [MSE:INV] Инвескор ХК (-4.84%)-ийн ханшийн бууралт зах зээлийг буурууллаа. ',
        'date': DateTime.now().toString(),
        'url': '',
        'source': 'Market News',
      },
      {
        'title': '4-р сард дотоодын хөрөнгийн зах 654 тэрбум төгрөгийн үнэлгээгээ алдав',
        'summary': 'Энэ оны гарснаас хойш дотоодын хөрөнгийн зах зээл тогтворгүй байсан ба ялангуяа 3 болон 4-р сард уналттай байлаа. 4-р сарын тоон үзүүлэлтийг харвал ТОП-20 индекс -2.46%-иар, I ангилалын MSE-A индекс -7.14%-ийн өндөр уналтыг үзүүлсэн бөгөөд үр дүнд нь хөрөнгийн зах -654.3 тэрбум төгрөгийн зах зээлийн үнэлгээгээ алдлаа.',
        'date': DateTime.now().toString(),
        'url': '',
        'source': 'Market News',
      }
    ];
  }

  Future<void> subscribeToSymbol(String symbol) async {
    try {
      _webSocketChannel?.sink.close();

      // Only connect to Binance WebSocket for crypto symbols
      if (symbol.toLowerCase().contains('btc') || symbol.toLowerCase().contains('eth')) {
        final wsUrl = 'wss://stream.binance.com:9443/ws/${symbol.toLowerCase()}@trade';
        print('Connecting to WebSocket: $wsUrl');

        _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

        _webSocketChannel!.stream.listen(
              (dynamic data) {
            try {
              Map<String, dynamic> tradeData;
              if (data is String) {
                tradeData = json.decode(data);
              } else if (data is Map) {
                tradeData = Map<String, dynamic>.from(data);
              } else {
                throw Exception('Unexpected data type: ${data.runtimeType}');
              }
              _dataStreamController.add(tradeData);
              print('Received WebSocket data for $symbol');
            } catch (e) {
              print('Error parsing WebSocket data: $e');
            }
          },
          onError: (error) {
            print('WebSocket error: $error');
          },
          onDone: () {
            print('WebSocket connection closed');
          },
        );

        print('Successfully subscribed to $symbol');
      } else {
        final mockData = _createMockMarketData();
        _dataStreamController.add(mockData);
      }
    } catch (e) {
      print('Error subscribing to symbol: $e');

      final mockData = _createMockMarketData();
      mockData['isMock'] = true;
      _dataStreamController.add(mockData);
    }
  }

  bool get hasError => _hasError;

  void dispose() {
    _refreshTimer?.cancel();
    _webSocketChannel?.sink.close();
    _dataStreamController.close();
  }
}

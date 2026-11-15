import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/holding.dart';
import '../models/mse_quote.dart';
import '../providers/mse_market_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/market_data_service.dart';
import '../services/trading_service.dart';
import '../widgets/trading_view_mobile_widget.dart';

class MarketScreen extends StatefulWidget {
  @override
  _MarketScreenState createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  late MarketDataService _marketDataService;
  late TabController _tabController;
  bool isLoading = true;
  String? error;
  List<Map<String, dynamic>> marketNews = [];
  Map<String, dynamic> liveMarketData = {};
  int refreshCounter = 0; // Used to force refresh TradingViewWidget
  bool isRefreshing = false;
  bool isMockData = false;
  String lastUpdated = '';
  final _storage = FlutterSecureStorage();
  final TradingService _tradingService = TradingService();

  // List of tradable crypto
  final List<Map<String, dynamic>> tradableCrypto = [
    {'symbol': 'BTC', 'name': 'Bitcoin', 'price': 104160.0},
    {'symbol': 'ETH', 'name': 'Ethereum', 'price': 2485.0},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeMarketData();
    _loadPreferences();
  }

  Future<void> _initializeMarketData() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      _marketDataService = MarketDataService();
      await _marketDataService.initialize();

      // Subscribe to market data updates
      _marketDataService.dataStream.listen(
            (data) {
          // Handle real-time market data updates
          setState(() {
            liveMarketData = data;
            isMockData = data['isMock'] == true;
            lastUpdated = DateTime.now()
                .toString()
                .substring(0, 19); // Format: YYYY-MM-DD HH:MM:SS
            refreshCounter++; // Increment to force refresh
            isLoading = false;
          });
          print('Received market data update: ${data.keys.toString()}');
        },
        onError: (e) {
          setState(() {
            error = e.toString();
            isLoading = false;
          });
          print('Market data stream error: $e');
        },
      );

      // Fetch market news
      try {
        final news = await _marketDataService.getMarketNews();
        if (mounted) {
          setState(() {
            marketNews = news;
          });
        }
      } catch (e) {
        print('Error fetching market news: $e');
        // Don't set global error for news failure
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          isLoading = false;
        });
      }
      print('Error initializing market data: $e');
    }
  }

  Future<void> _refreshCurrentTab() async {
    if (isRefreshing) return; // Prevent multiple refreshes

    final currentTab = _tabController.index;

    setState(() {
      isRefreshing = true;
    });

    try {
      if (currentTab == 0) {
        // MSE-ийн бодит ханшийг дахин татах
        await context.read<MseMarketProvider>().refresh();
      } else if (currentTab == 1) {
        // Refresh crypto
        setState(() {
          refreshCounter++;
        });
      } else if (currentTab == 2) {
        // Refresh news
        final news = await _marketDataService.getMarketNews();
        setState(() {
          marketNews = news;
        });
      }
    } catch (e) {
      print('Error refreshing: $e');
    } finally {
      setState(() {
        isRefreshing = false;
        lastUpdated = DateTime.now().toString().substring(0, 19);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _marketDataService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Зах зээлийн сүүлийн үеийн мэдээ'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Хувьцаа'),
            Tab(text: 'Крипто'),
            Tab(text: 'Мэдээ'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontSize: 16),
          indicatorColor: Colors.white,
          indicatorWeight: 3,
        ),
        actions: [
          if (isMockData)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Tooltip(
                message: 'Using demo data',
                child: Icon(Icons.data_array, color: Colors.orange),
              ),
            ),
          IconButton(
            icon: isRefreshing
                ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : Icon(Icons.refresh),
            onPressed: isRefreshing ? null : _refreshCurrentTab,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : error != null
          ? _buildErrorWidget()
          : RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildStocksTab(key: PageStorageKey('stocks-tab')),
            _buildCryptoTab(key: PageStorageKey('crypto-tab')),
            _buildNewsTab(key: PageStorageKey('news-tab')),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 48),
          SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              error!,
              style: TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializeMarketData,
            child: Text('Retry'),
          ),
          SizedBox(height: 8),
          TextButton(
            onPressed: () {
              // Clear the error and show mock data instead
              setState(() {
                error = null;
                isLoading = false;
                isMockData = true;
                refreshCounter++;
                lastUpdated = DateTime.now().toString().substring(0, 19);
              });
            },
            child: Text('Continue with Demo Data'),
          ),
        ],
      ),
    );
  }

  static final NumberFormat _money = NumberFormat('#,##0.##', 'en_US');
  static final NumberFormat _count = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _compact = NumberFormat.compact(locale: 'en_US');

  /// Хувьцааны таб: Монголын хөрөнгийн биржийн бодит ханш (open.mse.mn).
  Widget _buildStocksTab({Key? key}) {
    return Consumer<MseMarketProvider>(
      builder: (context, mse, _) {
        final stocks = mse.visibleSecurities;
        if (mse.isLoading && stocks.isEmpty) {
          return ListView(
            key: key,
            physics: AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: 160),
              Center(child: CircularProgressIndicator()),
              SizedBox(height: 12),
              Center(child: Text('MSE-ээс ханш татаж байна...')),
            ],
          );
        }

        return ListView.builder(
          key: key,
          physics: AlwaysScrollableScrollPhysics(), // Ensure pull-to-refresh works
          itemCount: stocks.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return _buildMseHeader(mse);
            final security = stocks[index - 1];
            final quote = mse.quoteFor(security.symbol);
            return _buildTradableAssetCard(
              symbol: security.symbol,
              name: security.name,
              price: quote?.price ?? 0,
              isStock: true,
              changePercent: quote?.changePercent,
              onTap: () => _showStockDetails(security),
            );
          },
        );
      },
    );
  }

  Widget _buildMseHeader(MseMarketProvider mse) {
    final marketOpen = mse.isMarketOpen;
    final updated = mse.lastUpdated;
    final updatedText = updated == null
        ? ''
        : ' · Шинэчлэгдсэн: ${DateFormat('HH:mm:ss').format(updated)}';

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle,
                  size: 10, color: marketOpen ? Colors.green : Colors.grey),
              SizedBox(width: 6),
              Text(
                marketOpen
                    ? 'Арилжаа явагдаж байна (1 мин тутам шинэчилнэ)'
                    : 'Арилжаа хаалттай · сүүлийн арилжааны ханш',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Spacer(),
              if (mse.isRefreshing)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            'Эх сурвалж: open.mse.mn$updatedText',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (mse.error != null) ...[
            SizedBox(height: 8),
            Text(mse.error!, style: TextStyle(color: Colors.red, fontSize: 12)),
          ],
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in [1, 2, 3])
                ChoiceChip(
                  label: Text('${['I', 'II', 'III'][c - 1]} ангилал'),
                  selected: mse.category == c,
                  onSelected: (_) => mse.setCategory(c),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Хувьцааны дэлгэрэнгүй: бүх арилжааны үзүүлэлт + 3 сарын график.
  void _showStockDetails(MseSecurity security) {
    final mse = context.read<MseMarketProvider>();
    final historyFuture = mse.historyFor(security.symbol);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Consumer<MseMarketProvider>(
          builder: (ctx, mse, _) {
            final q = mse.quoteFor(security.symbol);
            return ListView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(security.name, style: Theme.of(ctx).textTheme.titleLarge),
                Text(
                  '${security.symbol}${q != null && q.isin.isNotEmpty ? ' · ${q.isin}' : ''}',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 12),
                if (q == null)
                  Text('Ханш хараахан ирээгүй байна.')
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_money.format(q.price)}₮',
                        style: Theme.of(ctx)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 12),
                      Text(
                        '${q.change > 0 ? '+' : ''}${_money.format(q.change)} '
                        '(${q.changePercent > 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%)',
                        style: TextStyle(
                          fontSize: 16,
                          color: q.change > 0
                              ? Colors.green
                              : q.change < 0
                                  ? Colors.red
                                  : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _detailRow('Өмнөх хаалт', '${_money.format(q.previousClose)}₮'),
                  _detailRow('Нээлт', '${_money.format(q.open)}₮'),
                  _detailRow('Өдрийн хязгаар',
                      '${_money.format(q.dayLow)} – ${_money.format(q.dayHigh)}₮'),
                  _detailRow('VWAP', '${_money.format(q.vwap)}₮'),
                  _detailRow('Авах дээд үнэ',
                      '${_money.format(q.bidPrice)}₮ × ${_count.format(q.bidQty)}'),
                  _detailRow('Зарах доод үнэ',
                      '${_money.format(q.askPrice)}₮ × ${_count.format(q.askQty)}'),
                  _detailRow('Арилжигдсан ширхэг', _count.format(q.volume)),
                  _detailRow('Арилжааны дүн', '${_count.format(q.turnover)}₮'),
                  _detailRow('Хэлцлийн тоо', _count.format(q.trades)),
                  _detailRow('52 долоо хоног',
                      '${_money.format(q.week52Low)} – ${_money.format(q.week52High)}₮'),
                  _detailRow('Зах зээлийн үнэлгээ', '${_compact.format(q.marketCap)}₮'),
                ],
                SizedBox(height: 20),
                Text('Сүүлийн 3 сарын хаалтын ханш',
                    style: Theme.of(ctx).textTheme.titleMedium),
                SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: FutureBuilder<List<MseDailyBar>>(
                    future: historyFuture,
                    builder: (ctx, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                            child: Text('График татаж чадсангүй: ${snap.error}'));
                      }
                      return _buildHistoryChart(snap.data ?? []);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.grey[700]))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildHistoryChart(List<MseDailyBar> allBars) {
    final cutoff = DateTime.now().subtract(Duration(days: 92));
    var bars = allBars.where((b) => b.date.isAfter(cutoff)).toList();
    if (bars.length < 2) {
      // Сүүлийн 3 сард арилжаа бага байсан бол сүүлийн 60 арилжааг харуулна.
      bars = allBars.length > 60 ? allBars.sublist(allBars.length - 60) : allBars;
    }
    if (bars.length < 2) {
      return Center(child: Text('Арилжааны түүх хангалтгүй байна'));
    }

    final up = bars.last.close >= bars.first.close;
    final color = up ? Colors.green : Colors.red;
    final labelEvery = (bars.length / 4).ceilToDouble();

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Text(
                _compact.format(value),
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: labelEvery,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= bars.length) return SizedBox.shrink();
                return Text(
                  DateFormat('MM/dd').format(bars[i].date),
                  style: TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${DateFormat('yyyy-MM-dd').format(bars[s.x.toInt()].date)}\n'
                      '${_money.format(s.y)}₮',
                      TextStyle(color: Colors.white, fontSize: 12),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < bars.length; i++)
                FlSpot(i.toDouble(), bars[i].close),
            ],
            color: color,
            barWidth: 2,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withOpacity(0.12)),
          ),
        ],
      ),
    );
  }

  Widget _buildCryptoTab({Key? key}) {
    return ListView.builder(
      key: key,
      physics: AlwaysScrollableScrollPhysics(), // Ensure pull-to-refresh works
      itemCount: tradableCrypto.length + 3, // crypto + header + 2 charts
      itemBuilder: (context, index) {
        // Header with last updated
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lastUpdated.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Сүүлд шинэчлэгдсэн: $lastUpdated${isMockData ? ' (Demo)' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: isMockData ? Colors.orange : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Криптовалют',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          );
        }

        // Crypto assets
        if (index > 0 && index <= tradableCrypto.length) {
          final crypto = tradableCrypto[index - 1];
          return _buildTradableAssetCard(
            symbol: crypto['symbol'],
            name: crypto['name'],
            price: crypto['price'],
            isStock: false,
          );
        }

        // Bitcoin chart
        if (index == tradableCrypto.length + 1) {
          return Container(
            height: 350,
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bitcoin (BTC)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: TradingViewMobileWidget(
                        symbol: 'BTC',
                        isStockChart: false,
                        useMockData: isMockData,
                        liveData: liveMarketData,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Ethereum chart
        return Container(
          height: 350,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ethereum (ETH)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 8),
                  Expanded(
                    child: TradingViewMobileWidget(
                      symbol: 'ETH',
                      isStockChart: false,
                      useMockData: isMockData,
                      liveData: liveMarketData,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNewsTab({Key? key}) {
    if (marketNews.isEmpty) {
      return Center(
        key: key,
        child: isRefreshing
            ? CircularProgressIndicator()
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('Зах зээлийн мэдээ байхгүй байна'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                try {
                  setState(() {
                    isRefreshing = true;
                  });
                  final news = await _marketDataService.getMarketNews();
                  setState(() {
                    marketNews = news;
                    isRefreshing = false;
                  });
                } catch (e) {
                  setState(() {
                    isRefreshing = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                      Text('Failed to load news: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: Text('Дахин ачааллах'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      key: key,
      physics: AlwaysScrollableScrollPhysics(), // Ensure pull-to-refresh works
      itemCount: marketNews.length + 1, // +1 for the header
      itemBuilder: (context, index) {
        if (index == 0) {
          // Header with last updated time
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Зах зээлийн сүүлийн үеийн мэдээ',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (lastUpdated.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Сүүлд шинэчлэгдсэн: $lastUpdated${isMockData ? ' (Demo)' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: isMockData ? Colors.orange : Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        final newsIndex = index - 1;
        final news = marketNews[newsIndex];

        return Card(
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text(news['title'] ?? ''),
                ),
                if (isMockData)
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: Tooltip(
                      message: 'Demo content',
                      child: Icon(Icons.info_outline,
                          size: 16, color: Colors.orange),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                Text(news['summary'] ?? ''),
                SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      news['date'] ?? '',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    if (news['source'] != null)
                      Text(
                        news['source'],
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            onTap: () {
              // Handle news item tap
              if (news['url'] != null && news['url'].toString().isNotEmpty) {
                // Open URL if available
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Opening article...'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildTradableAssetCard({
    required String symbol,
    required String name,
    required double price,
    required bool isStock,
    double? changePercent,
    VoidCallback? onTap,
  }) {
    // Бодит өөрчлөлт мэдэгдэхгүй бол (жишээ нь крипто) хувийг харуулахгүй.
    final priceChange = changePercent;
    final canTrade = price > 0;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                  isStock ? Colors.blue.shade100 : Colors.amber.shade100,
                  child: Text(symbol[0]),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        symbol,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      canTrade ? '${_money.format(price)}\₮' : '—',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (priceChange != null)
                      Text(
                        '${priceChange > 0 ? '+' : ''}${priceChange.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: priceChange > 0
                              ? Colors.green
                              : priceChange < 0
                                  ? Colors.red
                                  : Colors.grey,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.add_circle_outline, color: Colors.white),
                    label: Text('Авах', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: !canTrade ? null : () {
                      _showTradeDialog(
                        context: context,
                        symbol: symbol,
                        name: name,
                        currentPrice: price,
                        isBuy: true,
                      );
                    },
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon:
                    Icon(Icons.remove_circle_outline, color: Colors.white),
                    label: Text('Зарах', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: !canTrade ? null : () {
                      _showTradeDialog(
                        context: context,
                        symbol: symbol,
                        name: name,
                        currentPrice: price,
                        isBuy: false,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  // In market_screen.dart - update the _showTradeDialog method
  void _showTradeDialog({
    required BuildContext context,
    required String symbol,
    required String name,
    required double currentPrice,
    required bool isBuy,
  }) {
    final portfolioProvider = Provider.of<PortfolioProvider>(context, listen: false);
    final TextEditingController quantityController = TextEditingController();
    final action = isBuy ? 'Авах' : 'Зарах';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              '$action $name ($symbol)',
              overflow: TextOverflow.ellipsis,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Одоогийн ханш: ${currentPrice.toStringAsFixed(2)}\₮'),
                SizedBox(height: 8),
                Text(isBuy
                    ? 'Дансны үлдэгдэл: ${portfolioProvider.cashBalance.toStringAsFixed(2)}\₮'
                    : 'Одоогийн Holdings: ${_getQuantityOwned(portfolioProvider, symbol).toStringAsFixed(2)} shares'),
                SizedBox(height: 16),
                TextField(
                  controller: quantityController,
                  decoration: InputDecoration(
                    labelText: 'ширхэгийг ${isBuy ? 'авах' : 'зарах'}',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    setState(() {}); // Update the UI when quantity changes
                  },
                ),
                SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final quantity = double.tryParse(quantityController.text) ?? 0;
                    final totalValue = quantity * currentPrice;
                    final canAfford = isBuy
                        ? portfolioProvider.cashBalance >= totalValue
                        : _getQuantityOwned(portfolioProvider, symbol) >= quantity;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Нийт үнэ: ${totalValue.toStringAsFixed(2)}\₮',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (isBuy && quantity > 0) Text(
                          'Үлдэгдэл: ${(portfolioProvider.cashBalance - totalValue).toStringAsFixed(2)}\₮',
                          style: TextStyle(
                            color: canAfford ? Colors.green : Colors.red,
                          ),
                        ),
                        if (!canAfford && quantity > 0) Text(
                          isBuy ? 'Үлдэгдэл хүрэлцэхгүй байна' : 'Хангалттай хувьцаа байхгүй байна',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text('Цуцлах'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
              ),
              Builder(
                builder: (context) {
                  final quantity = double.tryParse(quantityController.text) ?? 0;
                  final totalValue = quantity * currentPrice;
                  final canAfford = isBuy
                      ? portfolioProvider.cashBalance >= totalValue
                      : _getQuantityOwned(portfolioProvider, symbol) >= quantity;

                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBuy ? Colors.green : Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(action),
                    onPressed: quantity > 0 && canAfford ? () async {
                      Navigator.of(ctx).pop();

                      // Show loading indicator
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext context) {
                          return Dialog(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(width: 20),
                                  Text('${isBuy ? 'Худалдан авалт' : 'Заралт'} боловсруулж байна...'),
                                ],
                              ),
                            ),
                          );
                        },
                      );

                      try {
                        // Execute the trade
                        final success = isBuy
                            ? await portfolioProvider.buyStock(symbol, quantity, currentPrice)
                            : await portfolioProvider.sellStock(symbol, quantity, currentPrice);

                        // Close loading dialog
                        Navigator.of(context).pop();

                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Амжилттай ${isBuy ? 'худалдан авлаа' : 'зарлаа'}'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isBuy
                                  ? 'Худалдан авалт амжилтгүй боллоо'
                                  : 'Заралт амжилтгүй боллоо'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Алдаа гарлаа: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } : null,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  double _getQuantityOwned(PortfolioProvider provider, String symbol) {
    final holding = provider.holdings.firstWhere(
          (h) => h.symbol == symbol,
      orElse: () => Holding(symbol: symbol, quantity: 0, averageCost: 0),
    );
    return holding.quantity;
  }

  Future<void> _loadPreferences() async {
    try {
      // Load mock data preference
      String? useMockDataStr = await _storage.read(key: 'use_mock_data');
      setState(() {
        isMockData = useMockDataStr == 'true';
      });
    } catch (e) {
      print('Error loading preferences: $e');
    }
  }
}
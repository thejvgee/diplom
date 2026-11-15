import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/holding.dart';
import '../models/mse_quote.dart';
import '../providers/crypto_market_provider.dart';
import '../providers/mse_market_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/crypto_service.dart';

class MarketScreen extends StatefulWidget {
  @override
  _MarketScreenState createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  Future<void> _refreshCurrentTab() async {
    if (isRefreshing) return;
    setState(() => isRefreshing = true);
    try {
      if (_tabController.index == 1) {
        await context.read<CryptoMarketProvider>().refresh();
      } else {
        // Хувьцаа болон тойм хоёулаа MSE-ийн ханшаас
        await context.read<MseMarketProvider>().refresh();
      }
    } finally {
      if (mounted) setState(() => isRefreshing = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Зах зээл'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Хувьцаа'),
            Tab(text: 'Крипто'),
            Tab(text: 'Тойм'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontSize: 16),
          indicatorColor: Colors.white,
          indicatorWeight: 3,
        ),
        actions: [
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
      body: RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildStocksTab(key: PageStorageKey('stocks-tab')),
            _buildCryptoTab(key: PageStorageKey('crypto-tab')),
            _buildSummaryTab(key: PageStorageKey('summary-tab')),
          ],
        ),
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

  /// Крипто таб: Binance-ийн бодит ханш, төгрөгөөр.
  Widget _buildCryptoTab({Key? key}) {
    return Consumer<CryptoMarketProvider>(
      builder: (context, crypto, _) {
        final quotes = crypto.quotes;
        final rate = crypto.usdMnt;
        final updated = crypto.lastUpdated;
        return ListView(
          key: key,
          physics: AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Эх сурвалж: Binance · 1\$ = ${rate == null ? '—' : _money.format(rate)}₮'
                '${updated == null ? '' : ' · ${DateFormat('HH:mm:ss').format(updated)}'}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            if (crypto.error != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(crypto.error!,
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            if (quotes.isEmpty && crypto.error == null)
              Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              ),
            for (final q in quotes) ...[
              _buildTradableAssetCard(
                symbol: q.symbol,
                name: q.name,
                price: crypto.priceMnt(q.symbol),
                isStock: false,
                changePercent: q.changePercent,
              ),
              _buildCryptoChart(q, crypto.hourlyCloses(q.symbol)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCryptoChart(CryptoQuote q, List<double>? closes) {
    return Card(
      margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${q.name} — сүүлийн 48 цаг (USD)',
                style: Theme.of(context).textTheme.titleSmall),
            Text(
              '24ц хязгаар: \$${_money.format(q.lowUsd)} – \$${_money.format(q.highUsd)}',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: closes == null || closes.length < 2
                  ? Center(child: CircularProgressIndicator())
                  : _buildLineChart(closes),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(Icons.open_in_new, size: 16),
                label: Text('TradingView дээр нээх'),
                onPressed: () => launchUrl(
                  Uri.parse(
                      'https://www.tradingview.com/chart/?symbol=BINANCE:${q.symbol}USDT'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<double> values) {
    final up = values.last >= values.first;
    final color = up ? Colors.green : Colors.red;
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) =>
                  Text(_compact.format(v), style: TextStyle(fontSize: 10)),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i])
            ],
            color: color,
            barWidth: 2,
            dotData: FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: color.withOpacity(0.12)),
          ),
        ],
      ),
    );
  }

  /// Тойм таб: татсан бодит ханшаас өнөөдрийн зах зээлийн тоймыг гаргана
  /// (өмнөх зохиомол "мэдээ"-ний оронд).
  Widget _buildSummaryTab({Key? key}) {
    return Consumer<MseMarketProvider>(
      builder: (context, mse, _) {
        final quotes = [
          for (final s in mse.visibleSecurities)
            if (mse.quoteFor(s.symbol) != null) mse.quoteFor(s.symbol)!
        ];
        if (quotes.isEmpty) {
          return ListView(
            key: key,
            physics: AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: 160),
              Center(
                child: mse.isLoading
                    ? CircularProgressIndicator()
                    : Text('Ханшийн мэдээлэл алга'),
              ),
            ],
          );
        }
        final traded = quotes.where((q) => q.tradedToday).toList();
        final gainers = [...traded]
          ..sort((a, b) => b.changePercent.compareTo(a.changePercent));
        final losers = [...traded]
          ..sort((a, b) => a.changePercent.compareTo(b.changePercent));
        final active = [...traded]
          ..sort((a, b) => b.turnover.compareTo(a.turnover));
        final up = traded.where((q) => q.change > 0).length;
        final down = traded.where((q) => q.change < 0).length;
        final turnover = traded.fold<double>(0, (a, q) => a + q.turnover);
        const cats = ['I', 'II', 'III'];
        final updated = mse.lastUpdated;

        return ListView(
          key: key,
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(12),
          children: [
            Text(
              '${cats[mse.category - 1]} ангиллын ${quotes.length} хувьцаа · '
              'сүүлийн арилжааны өдөр · open.mse.mn'
              '${updated == null ? '' : ' · ${DateFormat('HH:mm').format(updated)}'}',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryStat('Арилжсан', '${traded.length}'),
                    _summaryStat('Өссөн', '$up', Colors.green),
                    _summaryStat('Буурсан', '$down', Colors.red),
                    _summaryStat('Нийт дүн', '${_compact.format(turnover)}₮'),
                  ],
                ),
              ),
            ),
            _summaryList('Хамгийн их өссөн',
                gainers.where((q) => q.change > 0).take(5), mse),
            _summaryList('Хамгийн их буурсан',
                losers.where((q) => q.change < 0).take(5), mse),
            _summaryList('Хамгийн идэвхтэй (арилжааны дүнгээр)',
                active.take(5), mse,
                showTurnover: true),
          ],
        );
      },
    );
  }

  Widget _summaryStat(String label, String value, [Color? color]) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );

  Widget _summaryList(
    String title,
    Iterable<MseQuote> items,
    MseMarketProvider mse, {
    bool showTurnover = false,
  }) {
    final list = items.toList();
    if (list.isEmpty) return SizedBox.shrink();
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            for (final q in list)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(q.symbol,
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(mse.securityFor(q.symbol)?.name ?? '',
                    overflow: TextOverflow.ellipsis),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(showTurnover
                        ? '${_compact.format(q.turnover)}₮'
                        : '${_money.format(q.price)}₮'),
                    Text(
                      '${q.changePercent > 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: q.change > 0
                            ? Colors.green
                            : q.change < 0
                                ? Colors.red
                                : Colors.grey,
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  final sec = mse.securityFor(q.symbol);
                  if (sec != null) _showStockDetails(sec);
                },
              ),
          ],
        ),
      ),
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
                      // Арилжааны цонхыг хаахаас өмнө дэлгэцийн (State)
                      // context-оос авна. Хаагдсан цонхны context-ийг await-ийн
                      // дараа ашиглавал "deactivated widget" алдаа гарна.
                      final screenContext = this.context;
                      final navigator = Navigator.of(screenContext);
                      final messenger = ScaffoldMessenger.of(screenContext);
                      Navigator.of(ctx).pop();

                      // Show loading indicator
                      showDialog(
                        context: screenContext,
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
                        navigator.pop();

                        if (success) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Амжилттай ${isBuy ? 'худалдан авлаа' : 'зарлаа'}'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(isBuy
                                  ? 'Худалдан авалт амжилтгүй боллоо'
                                  : 'Заралт амжилтгүй боллоо'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        navigator.pop();
                        messenger.showSnackBar(
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
}

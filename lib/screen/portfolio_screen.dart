import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import '../models/holding.dart';
import '../providers/mse_market_provider.dart';
import '../providers/portfolio_provider.dart';

class PortfolioScreen extends StatefulWidget {
  @override
  _PortfolioScreenState createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String selectedTimeRange = '1M';
  static final NumberFormat _money = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _compactMoney = NumberFormat.compact(locale: 'en_US');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title: Text('Миний Багц'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontSize: 16),
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'Тойм'),
            Tab(text: 'Хөрөнгө'),
            Tab(text: 'Гүйцэтгэл'),
          ],
        ),
      ),
      body: Consumer<PortfolioProvider>(
        builder: (context, portfolioProvider, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(portfolioProvider),
              _buildAssetsTab(portfolioProvider),
              _buildPerformanceTab(portfolioProvider),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddCashDialog(context);
        },
        child: Icon(Icons.add),
        tooltip: 'Данс цэнэглэх',
      ),
    );
  }

  // Overview Tab
  Widget _buildOverviewTab(PortfolioProvider portfolioProvider) {
    return FutureBuilder<double>(
        future: portfolioProvider.getTotalPortfolioValue(),
        builder: (context, snapshot) {
          double totalValue = snapshot.data ?? 0.0;
          double investedValue = totalValue - portfolioProvider.cashBalance;
          double investedPercentage =
          totalValue > 0 ? (investedValue / totalValue) * 100 : 0;
          double cashPercentage = totalValue > 0
              ? (portfolioProvider.cashBalance / totalValue) * 100
              : 0;

          // Ханш хамгийн сүүлд хэзээ шинэчлэгдсэн бэ (MSE)
          final mseUpdated = context.watch<MseMarketProvider>().lastUpdated;
          String lastUpdated = mseUpdated == null
              ? '—'
              : "${mseUpdated.hour}:${mseUpdated.minute.toString().padLeft(2, '0')}";

          double overallGainLoss = 0;
          double overallGainLossPercent = 0;

          if (portfolioProvider.holdings.isNotEmpty) {
            double totalCost = portfolioProvider.holdings
                .fold(0.0, (prev, holding) => prev + holding.totalCost);

            overallGainLoss = investedValue - totalCost;
            overallGainLossPercent =
            totalCost > 0 ? (overallGainLoss / totalCost) * 100 : 0;
          }

          // Find top performers and losers
          List<Holding> sortedHoldings = List.from(portfolioProvider.holdings);
          if (sortedHoldings.isNotEmpty) {
            sortedHoldings.sort((a, b) {
              return b.profitLossPercentage.compareTo(a.profitLossPercentage);
            });
          }

          List<Holding> topPerformers = sortedHoldings.take(3).toList();
          List<Holding> worstPerformers =
          sortedHoldings.reversed.take(3).toList();

          return ListView(
            padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            children: [
              // Portfolio summary KPIs
              _buildPortfolioHeader(totalValue, portfolioProvider,
                  overallGainLoss, overallGainLossPercent),

              // Last updated indicator
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 16.0),
                  child: Text(
                    'Сүүлд шинэчлэгдсэн: $lastUpdated',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              ),

              // Portfolio breakdown card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Багцын задаргаа',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildBreakdownItem(
                              'Хөрөнгө оруулсан',
                              '${investedValue.toStringAsFixed(2)}\₮',
                              '${investedPercentage.toStringAsFixed(1)}%',
                            ),
                          ),
                          Container(
                            height: 40,
                            width: 1,
                            color: Theme.of(context).dividerColor,
                          ),
                          Expanded(
                            child: _buildBreakdownItem(
                              'Хөрөнгө оруулаагүй',
                              '${portfolioProvider.cashBalance.toStringAsFixed(2)}\₮',
                              '${cashPercentage.toStringAsFixed(1)}%',
                            ),
                          ),
                        ],
                      ),
                      if (portfolioProvider.holdings.isNotEmpty) ...[
                        SizedBox(height: 16),
                        Divider(),
                        SizedBox(height: 16),
                        Text(
                          'Хөрөнгийн хуваарилалт',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        SizedBox(height: 8),
                        Container(
                          height: 400, // Increased height for better layout
                          child: _buildAssetAllocationChart(portfolioProvider),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24),

              // Top performers
              if (topPerformers.isNotEmpty) ...[
                Text(
                  'Ашигтай байгаа хувьцаанууд',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: 8),
                ...topPerformers.map(
                        (holding) => _buildPerformerItem(holding, isGainer: true)),
                SizedBox(height: 24),
              ],

              // Worst performers
              if (worstPerformers.isNotEmpty) ...[
                Text(
                  'Ашиггүй байгаа хувьцаанууд',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: 8),
                ...worstPerformers.map(
                        (holding) => _buildPerformerItem(holding, isGainer: false)),
                SizedBox(height: 24),
              ],

              // Holdings count
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Нийт хөрөнгө',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${portfolioProvider.holdings.length} holdings',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                      Icon(
                        Icons.analytics_outlined,
                        size: 28,
                        color: Theme.of(context).primaryColor,
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24),

              // View all holdings button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.visibility),
                  label: Text('Бүх holdings харах'),
                  onPressed: () {
                    _tabController.animateTo(1); // Switch to Assets tab
                  },
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              SizedBox(height: 32),
            ],
          );
        });
  }

  // Enhanced Portfolio Header
  Widget _buildPortfolioHeader(
      double totalValue,
      PortfolioProvider portfolioProvider,
      double overallGainLoss,
      double overallGainLossPercent,
      ) {
    bool isPositive = overallGainLossPercent >= 0;

    return Container(
      margin: EdgeInsets.symmetric(vertical: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Нийт багцын үнэлгээ',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).hintColor,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '${totalValue.toStringAsFixed(2)}\₮',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          SizedBox(height: 12),
          if (overallGainLoss != 0)
            Row(
              children: [
                Text(
                  'Нийт: ',
                  style: TextStyle(fontSize: 16),
                ),
                Text(
                  '${isPositive ? '+' : ''}${overallGainLoss.toStringAsFixed(2)}\₮ (${isPositive ? '+' : ''}${overallGainLossPercent.toStringAsFixed(2)}%)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isPositive ? Colors.black : Colors.black,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: isPositive ? Colors.black : Colors.black,
                )
              ],
            ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildKpiItem('Holdings', '${portfolioProvider.holdings.length}'),
              _buildKpiItem('Хөрөнгө оруулсан',
                  '${(totalValue - portfolioProvider.cashBalance).toStringAsFixed(2)}\₮'),
              _buildKpiItem('Үлдэгдэл',
                  '${portfolioProvider.cashBalance.toStringAsFixed(2)}\₮'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).hintColor,
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownItem(String label, String value, String percentage) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).hintColor,
          ),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          percentage,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).hintColor,
          ),
        ),
      ],
    );
  }

  Widget _buildAssetAllocationChart(PortfolioProvider provider) {
    return Consumer<PortfolioProvider>(
      builder: (context, provider, child) {
        // Calculate total portfolio value including cash
        final holdings = provider.holdings;
        final cashBalance = provider.cashBalance;
        final double totalValue = holdings.fold<double>(
          0.0,
              (sum, h) => sum + (h.quantity * h.effectivePrice),
        ) + cashBalance;

        if (totalValue == 0.0) {
          return Center(
            child: Text('Хувьцаа авж хөрөнгийн хуваарилалт харах'),
          );
        }

        // Define chart colors
        final List<Color> colors = [
          Colors.blue,
          Colors.green,
          Colors.red,
          Colors.purple,
          Colors.orange,
          Colors.teal,
          Colors.pink,
          Colors.cyan,
          Colors.amber,
          Colors.indigo,
        ];

        // Build pie chart sections for each holding
        List<PieChartSectionData> sections = [];
        for (int i = 0; i < holdings.length; i++) {
          final holding = holdings[i];
          final holdingValue = holding.quantity * holding.effectivePrice;
          if (holdingValue > 0) {
            final percentage = (holdingValue / totalValue) * 100;
            sections.add(
              PieChartSectionData(
                color: colors[i % colors.length],
                value: holdingValue,
                title: percentage > 5 ? '${percentage.toStringAsFixed(0)}%' : '',
                titleStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                radius: 50,
                titlePositionPercentageOffset: 0.55,
              ),
            );
          }
        }

        // Add cash balance as a section
        if (cashBalance > 0) {
          final cashPct = (cashBalance / totalValue) * 100;
          sections.add(
            PieChartSectionData(
              color: Colors.grey[300]!,
              value: cashBalance,
              title: cashPct > 5 ? '${cashPct.toStringAsFixed(0)}%' : '',
              titleStyle: TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              radius: 50,
              titlePositionPercentageOffset: 0.55,
              badgeWidget: cashPct > 10
                  ? Text(
                'Үлдэгдэл',
                style: TextStyle(fontSize: 10, color: Colors.black),
              )
                  : null,
              badgePositionPercentageOffset: 0.98,
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1.5,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 30,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is FlTapUpEvent && response?.touchedSection != null) {
                        final idx = response!.touchedSection!.touchedSectionIndex;
                        String message;
                        if (idx < holdings.length) {
                          final h = holdings[idx];
                          final val = h.quantity * h.effectivePrice;
                          final pct = (val / totalValue) * 100;
                          message = '${h.symbol}: ${pct.toStringAsFixed(1)}%';
                        } else {
                          message = 'Үлдэгдэл: ${(cashBalance/totalValue*100).toStringAsFixed(1)}%';
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                // Legend for holdings
                ...holdings.asMap().entries.map((entry) {
                  final holding = entry.value;
                  final value = holding.quantity * holding.effectivePrice;
                  final pct = (value / totalValue) * 100;
                  return _buildLegendItem(
                    '${holding.symbol} (${pct.toStringAsFixed(1)}%)',
                    colors[entry.key % colors.length],
                  );
                }).toList(),
                // Legend for cash
                if (cashBalance > 0)
                  _buildLegendItem(
                    'Үлдэгдэл (${(cashBalance / totalValue * 100).toStringAsFixed(1)}%)',
                    Colors.grey[300]!,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPerformerItem(Holding holding, {required bool isGainer}) {
    double gainLossPercent = holding.profitLossPercentage;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              holding.symbol[0],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holding.symbol,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'ширхэг:${holding.quantity.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${holding.effectivePrice.toStringAsFixed(2)}\₮',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  color: Colors.black,
                ),
              ),
              Row(
                children: [
                  Icon(
                    gainLossPercent >= 0
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 12,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  Text(
                    '${gainLossPercent.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Assets Tab
  Widget _buildAssetsTab(PortfolioProvider portfolioProvider) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _buildCashCard(portfolioProvider),
        SizedBox(height: 16),
        Text('Таны хөрөнгө оруулалт',
            style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 8),
        ...portfolioProvider.holdings
            .map((holding) => _buildAssetCard(holding)),
      ],
    );
  }

  static const Map<String, int> _rangeDays = {
    '1W': 7,
    '1M': 30,
    '3M': 90,
    '1Y': 365,
    'Бүгд': 100000,
  };

  // Гүйцэтгэлийн таб: багцын өдөр тутмын бодит үнэлгээний түүх
  Widget _buildPerformanceTab(PortfolioProvider portfolioProvider) {
    final days = _rangeDays[selectedTimeRange] ?? 30;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final points = portfolioProvider.valueHistory
        .where((p) => p.day.isAfter(cutoff))
        .toList();

    return Column(
      children: [
        _buildTimeRangeSelector(),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: points.length < 2
                ? Center(
                    child: Text(
                      'Багцын үнэлгээний түүх хуримтлагдаж байна.\n'
                      'Апп-ыг өдөр бүр нээхэд график бүрдэнэ.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  )
                : _buildValueChart(points),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16),
          child: _buildPerformanceSummary(portfolioProvider),
        ),
      ],
    );
  }

  Widget _buildValueChart(List<ValuePoint> points) {
    final values = points.map((p) => p.value).toList();
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxV - minV).abs() < 1 ? maxV * 0.01 + 1 : (maxV - minV) * 0.1;
    final up = values.last >= values.first;
    final color = up ? Colors.green : Colors.red;
    final step = (points.length / 4).ceilToDouble();

    return LineChart(
      LineChartData(
        minY: minV - pad,
        maxY: maxV + pad,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value)
            ],
            color: color,
            barWidth: 2,
            dotData: FlDotData(show: points.length < 15),
            belowBarData:
                BarAreaData(show: true, color: color.withOpacity(0.1)),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) => Text(
                _compactMoney.format(value),
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: step,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return SizedBox.shrink();
                final d = points[i].day;
                return Text('${d.month}/${d.day}',
                    style: TextStyle(fontSize: 10));
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  // Time Range Selector
  Widget _buildTimeRangeSelector() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _rangeDays.keys.map((range) {
          final selected = selectedTimeRange == range;
          return GestureDetector(
            onTap: () => setState(() => selectedTimeRange = range),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).primaryColor
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                range,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Гүйцэтгэлийн дүгнэлт: өнөөдөр (MSE-ийн өмнөх хаалттай харьцуулж),
  // 7 хоног ба сар (хадгалсан үнэлгээний түүхээр)
  Widget _buildPerformanceSummary(PortfolioProvider portfolioProvider) {
    final total = portfolioProvider.totalValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Гүйцэтгэлийн дүгнэлт',
            style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 12),
        _buildPerformanceItem('Өнөөдөр', portfolioProvider.dayChange, total),
        SizedBox(height: 8),
        _buildPerformanceItem(
            'Өнгөрсөн 7 хоног', portfolioProvider.changeSince(7), total),
        SizedBox(height: 8),
        _buildPerformanceItem(
            'Өнгөрсөн сар', portfolioProvider.changeSince(30), total),
      ],
    );
  }

  // Performance Item (change == null → өгөгдөл хараахан хүрэлцэхгүй)
  Widget _buildPerformanceItem(String period, double? change, double total) {
    if (change == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(period, style: TextStyle(fontSize: 16)),
          Text('Түүх хүрэлцэхгүй',
              style: TextStyle(color: Theme.of(context).hintColor)),
        ],
      );
    }
    final base = total - change;
    final percentChange = base > 0 ? (change / base) * 100 : 0.0;
    final isPositive = change >= 0;
    final color = change > 0
        ? Colors.green
        : change < 0
            ? Colors.red
            : Theme.of(context).textTheme.bodyLarge?.color;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(period, style: TextStyle(fontSize: 16)),
        Row(
          children: [
            Text(
              '${isPositive ? '+' : ''}${_money.format(change)}₮',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            SizedBox(width: 8),
            Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12, color: color),
            Text('${percentChange.toStringAsFixed(2)}%',
                style: TextStyle(color: color)),
          ],
        ),
      ],
    );
  }


  // Helper Widgets
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAssetDetailItem(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color ?? Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ],
    );
  }

  // Cash Card for Assets Tab
  Widget _buildCashCard(PortfolioProvider portfolioProvider) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Icon(Icons.attach_money,
                  color: Theme.of(context).primaryColor),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Дансны үлдэгдэл',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Хөрөнгө оруулалт хийх боломжтой',
                    style: TextStyle(
                        color: Theme.of(context).hintColor, fontSize: 14),
                  ),
                ],
              ),
            ),
            Text(
              '${portfolioProvider.cashBalance.toStringAsFixed(2)}\₮',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  // Asset Card for Assets Tab
  Widget _buildAssetCard(Holding holding) {
    final currentValue = holding.currentValue;
    final gainLossPercent = holding.profitLossPercentage;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                  Theme.of(context).primaryColor.withOpacity(0.1),
                  child: Text(
                    holding.symbol[0],
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        holding.symbol,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Одоогоор: ${holding.effectivePrice.toStringAsFixed(2)}\₮ | Дундаж: ${holding.averageCost.toStringAsFixed(2)}\₮',
                        style: TextStyle(
                            color: Theme.of(context).hintColor, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAssetDetailItem(
                    'Тоо ширхэг', '${holding.quantity.toStringAsFixed(2)}'),
                _buildAssetDetailItem(
                    'Таньд байгаа', '${currentValue.toStringAsFixed(2)}\₮'),
                _buildAssetDetailItem(
                  'Өөрчлөлт',
                  '${gainLossPercent.toStringAsFixed(2)}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Add Cash Dialog
  void _showAddCashDialog(BuildContext context) {
    final TextEditingController amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Дансаа цэнэглэх'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: InputDecoration(
                labelText: 'Дүн (\₮)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: Text('Цуцлах'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text);
              if (amount != null && amount > 0) {
                final portfolioProvider =
                Provider.of<PortfolioProvider>(context, listen: false);
                portfolioProvider.addCash(amount);
                Navigator.of(ctx).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${amount.toStringAsFixed(2)} \₮ таны данс руу нэмэгдлээ'),
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Бүхэл тоо оруулна уу!'),
                    backgroundColor: Colors.black,
                  ),
                );
              }
            },
            child: Text('Нэмэх'),
          ),
        ],
      ),
    );
  }
}

// Asset Detail Screen
class AssetDetailScreen extends StatelessWidget {
  final String assetName;
  final Map<String, dynamic> assetData;

  const AssetDetailScreen({
    Key? key,
    required this.assetName,
    required this.assetData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(assetName),
      ),
      body: Center(
        child: Text('Asset Details Coming Soon'),
      ),
    );
  }
}
import 'package:flutter/material.dart';

import '../services/ai_financial_service.dart';
import '../widgets/trading_view_widget.dart';

class AIFinancialScreen extends StatefulWidget {
  final String geminiApiKey;

  const AIFinancialScreen({
    Key? key,
    required this.geminiApiKey,
  }) : super(key: key);

  @override
  _AIFinancialScreenState createState() => _AIFinancialScreenState();
}

class _AIFinancialScreenState extends State<AIFinancialScreen>
    with SingleTickerProviderStateMixin {
  late AIFinancialService _aiService;
  late TabController _tabController;
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _portfolioAnalysis;
  Map<String, dynamic>? _recommendations;
  String _selectedSymbol = 'AARD';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _aiService = AIFinancialService(geminiApiKey: widget.geminiApiKey);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load portfolio analysis
      final portfolio = [
        {'symbol': 'AARD', 'shares': 30, 'avgPrice': 1200.0},
        {'symbol': 'ADB', 'shares': 10, 'avgPrice': 900.0},
        {'symbol': 'APU', 'shares': 20, 'avgPrice': 1400.0},
        {'symbol': 'BODI', 'shares': 20, 'avgPrice': 2500.0},
        {'symbol': 'SUU', 'shares': 10, 'avgPrice': 1800.0},
        {'symbol': 'GLMT', 'shares': 10, 'avgPrice': 3000.0},
        {'symbol': 'KHAN', 'shares': 90, 'avgPrice': 1070.0},
        {'symbol': 'LEND', 'shares': 40, 'avgPrice': 150.0},
        {'symbol': 'MSE', 'shares': 30, 'avgPrice': 290.0},
        {'symbol': 'TTL', 'shares': 200, 'avgPrice': 29000.0}
      ];
      _portfolioAnalysis = await _aiService.analyzePortfolio(portfolio);

      // Load recommendations
      _recommendations = await _aiService.getStockRecommendations(
        riskLevel: 'Moderate',
        investmentAmount: 10000,
        preferredSectors: ['Technology', 'Healthcare'],
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
        title: Text('Санхүүгийн AI зөвлөх'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Багц'),
            Tab(text: 'Зөвлөмж'),
            Tab(text: 'Анализ'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorWidget()
          : TabBarView(
        controller: _tabController,
        children: [
          _buildPortfolioTab(),
          _buildRecommendationsTab(),
          _buildAnalysisTab(),
        ],
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
          Text(
            _error!,
            style: TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadInitialData,
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioTab() {
    if (_portfolioAnalysis == null)
      return Center(child: Text('Багцын мэдээлэл алга'));

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Багцын тойм',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: 16),
                _buildPortfolioMetric(
                  'Нийт хөрөнгө',
                  '${_portfolioAnalysis!['totalValue']?.toStringAsFixed(2) ?? '0.00'} ₮',
                ),
                _buildPortfolioMetric(
                  'Өдөр тутмын өөрчлөлт',
                  '${_portfolioAnalysis!['dailyChange']?.toStringAsFixed(2) ?? '0.00'}%',
                  isPositive:
                  _portfolioAnalysis!['dailyChange']?.isPositive ?? false,
                ),
                _buildPortfolioMetric(
                  'Эрсдлийн оноо',
                  '${_portfolioAnalysis!['riskScore']?.toStringAsFixed(1) ?? '0.0'}/10',
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Хиймэл оюун зөвлөмж',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: 16),
                Text(_portfolioAnalysis!['recommendations'] ??
                    'Зөвлөмж байхгүй байна'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationsTab() {
    if (_recommendations == null)
      return Center(child: Text('Зөвлөмж байхгүй байна'));

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _recommendations!['recommendations']?.length ?? 0,
      itemBuilder: (context, index) {
        final recommendation = _recommendations!['recommendations'][index];
        return Card(
          margin: EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      recommendation['symbol'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      recommendation['rating'],
                      style: TextStyle(
                        color: recommendation['rating'] == 'Buy'
                            ? Colors.green
                            : recommendation['rating'] == 'Sell'
                            ? Colors.red
                            : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  recommendation['summary'],
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                SizedBox(height: 8),
                Text(
                  'Эрсдлийн түвшин: ${recommendation['riskLevel']}',
                  style: TextStyle(
                    color: recommendation['riskLevel'] == 'Low'
                        ? Colors.green
                        : recommendation['riskLevel'] == 'High'
                        ? Colors.red
                        : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnalysisTab() {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Техник шинжилгээ',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: 16),
                TradingViewWidget(
                  symbol: _selectedSymbol,
                  isStockChart: true,
                  height: 300,
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final analysis =
                    await _aiService.getTechnicalAnalysis(_selectedSymbol);
                    _showAnalysisDialog('Техник шинжилгээ', analysis);
                  },
                  child: Text('Техник шинжилгээ харах'),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Үндсэн шинжилгээ',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final analysis = await _aiService
                        .getFundamentalAnalysis(_selectedSymbol);
                    _showAnalysisDialog('Үндсэн шинжилгээ', analysis);
                  },
                  child: Text('Үндсэн шинжилгээ харах'),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Зах зээлийн чиг хандлага',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final analysis = await _aiService
                        .analyzeMarketSentiment(_selectedSymbol);
                    _showAnalysisDialog('Зах зээлийн чиг хандлага', analysis);
                  },
                  child: Text('Зах зээлийн чиг хандлага харах'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortfolioMetric(String label, String value, {bool? isPositive}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isPositive != null
                  ? (isPositive ? Colors.green : Colors.red)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  void _showAnalysisDialog(String title, Map<String, dynamic> analysis) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(analysis['summary'] ?? 'Дүгнэлт байхгүй байна'),
              SizedBox(height: 16),
              Text(
                'Үндсэн санаа:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...(analysis['keyPoints'] as List<dynamic>? ?? []).map(
                    (point) => Padding(
                  padding: EdgeInsets.only(left: 16, top: 4),
                  child: Text('• $point'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Хаах'),
          ),
        ],
      ),
    );
  }
}

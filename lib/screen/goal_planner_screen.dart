import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../ai_engine/advisor_engine.dart';
import '../ai_engine/goal_planner.dart';
import '../ai_engine/risk_profile.dart';
import '../providers/advisor_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/user_preferences_provider.dart';

/// "N жилд X төгрөг хуримтлуулах" зорилгын төлөвлөгөө (Monte Carlo).
class GoalPlannerScreen extends StatefulWidget {
  const GoalPlannerScreen({super.key});

  @override
  State<GoalPlannerScreen> createState() => _GoalPlannerScreenState();
}

class _GoalPlannerScreenState extends State<GoalPlannerScreen> {
  static final NumberFormat _money = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _compact = NumberFormat.compact(locale: 'en_US');

  final _target = TextEditingController(text: '20,000,000');
  final _initial = TextEditingController();
  final _cashRate = TextEditingController(text: '10');
  final _inflation = TextEditingController(text: '7');
  final _fee = TextEditingController(text: '1');
  bool _glidePath = true;
  int _years = 3;
  String? _riskKey;
  GoalPlan? _plan;
  double _monthly = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final portfolio = context.read<PortfolioProvider>();
    _initial.text = _money.format(portfolio.totalValue);
    _riskKey = context.read<UserPreferencesProvider>().riskTolerance;
  }

  @override
  void dispose() {
    _target.dispose();
    _initial.dispose();
    _cashRate.dispose();
    _inflation.dispose();
    _fee.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();
    final target = _parse(_target);
    if (target <= 0) {
      setState(() => _error = 'Зорилтот дүнгээ оруулна уу');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(Duration.zero); // ачааллын тэмдэг харагдуулах
    final advisor = context.read<AdvisorProvider>();
    await advisor.load();
    final market = advisor.signals?.modelMetrics['market'];
    final assumptions = MarketAssumptions.fromMetrics(
      market is Map ? Map<String, dynamic>.from(market) : null,
      cashAnnualRate: (_parse(_cashRate) / 100).clamp(0.0, 0.5),
      inflationAnnual: (_parse(_inflation) / 100).clamp(0.0, 0.5),
      annualFee: (_parse(_fee) / 100).clamp(0.0, 0.1),
    );
    final profile = RiskProfile.fromKey(_riskKey ?? 'Moderate');
    final plan = GoalPlanner(assumptions).plan(
      target: target,
      years: _years,
      initial: _parse(_initial),
      stockShare: 1 - profile.targetCash,
      glidePath: _glidePath,
    );
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _monthly = _roundUp(plan.requiredMonthly(0.8));
      _busy = false;
    });
  }

  static double _roundUp(double v) {
    if (!v.isFinite) return v;
    const step = 10000.0;
    return (v / step).ceil() * step;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Зорилгын төлөвлөгөө')),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildInputs(),
          SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              icon: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.calculate),
              label: Text('Тооцоолох'),
              onPressed: _busy ? null : _calculate,
            ),
          ),
          if (_error != null) ...[
            SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red)),
          ],
          if (_plan != null) ...[
            SizedBox(height: 16),
            _buildResult(_plan!),
          ],
        ],
      ),
    );
  }

  Widget _buildInputs() {
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))];
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              inputFormatters: money,
              decoration: InputDecoration(
                labelText: 'Зорилтот дүн (₮)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _initial,
              keyboardType: TextInputType.number,
              inputFormatters: money,
              decoration: InputDecoration(
                labelText: 'Одоо байгаа мөнгө (₮)',
                helperText: 'Анхдагчаар таны багцын нийт үнэлгээ',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            Text('Хугацаа: $_years жил'),
            Slider(
              value: _years.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              label: '$_years жил',
              onChanged: (v) => setState(() => _years = v.round()),
            ),
            DropdownButtonFormField<String>(
              value: _riskKey,
              decoration: InputDecoration(
                labelText: 'Эрсдэлийн профайл',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in RiskProfile.all)
                  DropdownMenuItem(
                    value: p.key,
                    child: Text('${p.label} — хувьцаа '
                        '${((1 - p.targetCash) * 100).round()}%'),
                  ),
              ],
              onChanged: (v) => setState(() => _riskKey = v),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _cashRate,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Хадгаламжийн жилийн хүү (%)',
                helperText: 'Бэлэн мөнгөний хэсэгт тооцох хүү — өөрийн банкныхаар солино уу',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inflation,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Инфляци (%/жил)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _fee,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Зардал (%/жил)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              'Бүх дүнг өнөөгийн мөнгөний үнэ цэнээр (инфляцийг хасаж) тооцно.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Зорилгод ойртох тусам эрсдэл бууруулах'),
              subtitle: Text('Сүүлийн 3 жилд хувьцааны хувийг аажмаар багасгана'),
              value: _glidePath,
              onChanged: (v) => setState(() => _glidePath = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(GoalPlan plan) {
    final c50 = plan.requiredMonthly(0.5);
    final c80 = plan.requiredMonthly(0.8);
    final prob = plan.probability(_monthly);
    final bands = plan.bands(_monthly);
    final median = bands[1].last;
    final sliderMax = _roundUp(
        (c80.isFinite ? c80 : plan.target / plan.months) * 2 + 10000);
    final probColor = prob >= 0.75
        ? Colors.green.shade700
        : prob >= 0.5
            ? Colors.orange.shade800
            : Colors.red.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_money.format(plan.target)}₮-д ${plan.years} жилд хүрэхийн тулд',
                    style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: 12),
                _requirement('50% магадлалтай', c50),
                _requirement('80% магадлалтай', c80),
              ],
            ),
          ),
        ),
        SizedBox(height: 12),
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Сард ${_money.format(_monthly)}₮ хуримтлуулбал',
                    style: Theme.of(context).textTheme.titleMedium),
                Slider(
                  value: _monthly.clamp(0, sliderMax).toDouble(),
                  min: 0,
                  max: sliderMax,
                  divisions: 100,
                  onChanged: (v) => setState(() => _monthly = _roundUp(v)),
                ),
                Row(
                  children: [
                    Text('Зорилгод хүрэх магадлал: '),
                    Text('${(prob * 100).round()}%',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: probColor)),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Хүлээгдэх дүн (медиан): ${_money.format(median)}₮ · '
                  'нийт хуримтлуулах: ${_money.format(plan.totalContributed(_monthly))}₮',
                  style: TextStyle(fontSize: 12),
                ),
                Text(
                  'Хамгийн муу 10% хувилбарт дунджаар: '
                  '${_money.format(plan.worstTenPercent(_monthly))}₮',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
                SizedBox(height: 16),
                SizedBox(height: 220, child: _buildFanChart(plan, bands)),
                SizedBox(height: 8),
                Text(
                  'Ногоон муж: 10%–90%-ийн хүрээ, зураас: медиан, '
                  'улаан тасархай: зорилго.',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 12),
        _buildAssumptions(plan),
      ],
    );
  }

  Widget _requirement(String label, double monthly) => Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              monthly.isFinite
                  ? (monthly <= 0 ? 'нэмэлт шаардлагагүй' : 'сард ${_money.format(_roundUp(monthly))}₮')
                  : 'хүрэх боломжгүй',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );

  Widget _buildFanChart(GoalPlan plan, List<List<double>> bands) {
    final low = bands[0], mid = bands[1], high = bands[2];
    List<FlSpot> spots(List<double> v) =>
        [for (var k = 0; k < v.length; k++) FlSpot(k.toDouble(), v[k])];
    final maxY = [high.reduce((a, b) => a > b ? a : b), plan.target]
            .reduce((a, b) => a > b ? a : b) *
        1.05;
    final lowBar = LineChartBarData(
        spots: spots(low), color: Colors.transparent, dotData: FlDotData(show: false));
    final highBar = LineChartBarData(
        spots: spots(high), color: Colors.transparent, dotData: FlDotData(show: false));

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          lowBar,
          highBar,
          LineChartBarData(
            spots: spots(mid),
            color: Colors.green.shade800,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
        ],
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 0,
            toIndex: 1,
            color: Colors.green.withValues(alpha: 0.18),
          ),
        ],
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: plan.target,
            color: Colors.red,
            strokeWidth: 1.5,
            dashArray: [6, 4],
          ),
        ]),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) =>
                  Text(_compact.format(v), style: TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (plan.years / 5).ceilToDouble().clamp(1, 10),
              getTitlesWidget: (v, meta) =>
                  Text('${v.toInt()}ж', style: TextStyle(fontSize: 10)),
            ),
          ),
        ),
        gridData: FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(enabled: false),
      ),
    );
  }

  Widget _buildAssumptions(GoalPlan plan) {
    final a = plan.assumptions;
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Таамаглал', style: Theme.of(context).textTheme.titleSmall),
            SizedBox(height: 6),
            Text(
              '• Хувьцаа ${pct(plan.stockShare)}'
              '${plan.glidePath && plan.finalStockShare < plan.stockShare ? ' → эцэст нь ${pct(plan.finalStockShare)}' : ''}, '
              'үлдсэн нь хадгаламж (сар бүр тэнцвэржүүлнэ)\n'
              '• Хувьцааны өгөөж: ${a.usesBootstrap ? 'MSE-ийн бодит сарын өгөөжөөс 3 сарын блокоор санамсаргүй сонгосон (bootstrap)' : 'лог-нормаль тархалт'} '
              '— ${a.source}, жилд ~${pct(a.stockAnnualReturn)}, хэлбэлзэл ≥${pct(a.stockAnnualVol)}\n'
              '• Хадгаламжийн хүү ${pct(a.cashAnnualRate)}, инфляци ${pct(a.inflationAnnual)}, '
              'хувьцааны зардал ${pct(a.annualFee)}/жил\n'
              '• 2,000 санамсаргүй хувилбар (Monte Carlo); дүн өнөөгийн мөнгөөр, татвар тооцоогүй',
              style: TextStyle(fontSize: 12),
            ),
            SizedBox(height: 8),
            Text(AdvisorEngine.disclaimer,
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}

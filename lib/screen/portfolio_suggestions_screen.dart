import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../ai_engine/advisor_engine.dart';
import '../ai_engine/risk_profile.dart';
import '../providers/advisor_provider.dart';
import '../providers/mse_market_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/user_preferences_provider.dart';
import '../widgets/signal_explanation.dart';
import 'goal_planner_screen.dart';

/// Өөрийн AI зөвлөхийн дэлгэц (Gemini-гүй, утсан дээр тооцоолно).
class PortfolioSuggestionsScreen extends StatefulWidget {
  @override
  _PortfolioSuggestionsScreenState createState() =>
      _PortfolioSuggestionsScreenState();
}

class _PortfolioSuggestionsScreenState
    extends State<PortfolioSuggestionsScreen> {
  static final NumberFormat _money = NumberFormat('#,##0', 'en_US');
  bool _isGenerating = false;
  bool _shouldShowIntro = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdvisorProvider>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final advisor = context.watch<AdvisorProvider>();
    final userPreferences = context.watch<UserPreferencesProvider>();
    final report = advisor.report;

    return Scaffold(
      appBar: AppBar(title: Text('Санал болгох багц')),
      body: _isGenerating
          ? _buildLoadingState()
          : report != null
              ? _buildReportView(report, advisor)
              : _buildInitialState(advisor, userPreferences),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Таны багцад шинжилгээ хийж байна...',
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildInitialState(
    AdvisorProvider advisor,
    UserPreferencesProvider userPreferences,
  ) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_shouldShowIntro) _buildIntroSection(),
          SizedBox(height: 16),
          _buildRiskToleranceSelector(userPreferences),
          SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              icon: Icon(Icons.auto_awesome),
              label: Text('Санал болгох багц боловсруулах'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: advisor.isLoading ? null : _generate,
            ),
          ),
          SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(Icons.flag_outlined),
            label: Text('Зорилгын төлөвлөгөө (N жилд X₮)'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GoalPlannerScreen()),
            ),
          ),
          if (advisor.error != null) ...[
            SizedBox(height: 16),
            _errorBox(advisor.error!),
          ],
          SizedBox(height: 16),
          if (advisor.signals != null) _buildModelInfo(advisor.signals!.modelMetrics,
              advisor.signals!.generatedAt),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final portfolio = context.read<PortfolioProvider>();
    final prefs = context.read<UserPreferencesProvider>();
    final mse = context.read<MseMarketProvider>();
    setState(() => _isGenerating = true);
    try {
      await context.read<AdvisorProvider>().analyze(
            holdings: portfolio.holdings,
            cash: portfolio.cashBalance,
            riskTolerance: prefs.riskTolerance,
            livePrices: mse.lastPrices,
          );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Widget _buildIntroSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text('AI Санал болгох багц',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Манай өөрийн AI загвар Монголын хөрөнгийн биржийн 12+ жилийн '
              'арилжааны өгөгдлөөр сурсан. Дараах зүйлст тулгуурлан зөвлөгөө өгнө:',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            SizedBox(height: 8),
            _buildFeatureItem('Таны одоогийн багц ба бэлэн мөнгө'),
            _buildFeatureItem('Хувьцаа бүрийн өсөх магадлал (өөрийн загвар)'),
            _buildFeatureItem('Хэлбэлзэл, корреляци, хөрвөх чадвар'),
            _buildFeatureItem('Таны эрсдэлийн профайл'),
            SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                child: Text('Нуух'),
                onPressed: () => setState(() => _shouldShowIntro = false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildRiskToleranceSelector(UserPreferencesProvider userPreferences) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Таны эрсдэлийн түвшин',
                style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: userPreferences.riskTolerance,
              decoration: InputDecoration(
                labelText: 'Эрсдэлийн түвшин',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in RiskProfile.all)
                  DropdownMenuItem(value: p.key, child: Text(p.label)),
              ],
              onChanged: (v) {
                if (v != null) userPreferences.setRiskTolerance(v);
              },
            ),
            SizedBox(height: 8),
            TextButton.icon(
              icon: Icon(Icons.quiz_outlined),
              label: Text('Мэдэхгүй байна уу? Асуумж бөглөх'),
              onPressed: () => _showQuestionnaire(userPreferences),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuestionnaire(UserPreferencesProvider prefs) async {
    final answers = List<int?>.filled(RiskQuestionnaire.questions.length, null);
    final result = await showDialog<RiskProfile>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Эрсдэлийн асуумж'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var q = 0; q < RiskQuestionnaire.questions.length; q++) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      '${q + 1}. ${RiskQuestionnaire.questions[q].text}',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (var o = 0;
                      o < RiskQuestionnaire.questions[q].options.length;
                      o++)
                    RadioListTile<int>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(RiskQuestionnaire.questions[q].options[o]),
                      value: o,
                      groupValue: answers[q],
                      onChanged: (v) => setDialog(() => answers[q] = v),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Цуцлах'),
            ),
            ElevatedButton(
              onPressed: answers.contains(null)
                  ? null
                  : () => Navigator.pop(
                        ctx,
                        RiskQuestionnaire.evaluate(answers.cast<int>()),
                      ),
              child: Text('Дүгнэх'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await prefs.setRiskTolerance(result.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Таны эрсдэлийн профайл: ${result.label}')),
    );
  }

  // ---------------------------------------------------------------------------
  // Үр дүн
  // ---------------------------------------------------------------------------

  Widget _buildReportView(AdvisorReport report, AdvisorProvider advisor) {
    return RefreshIndicator(
      onRefresh: _generate,
      child: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildHealthCard(report),
          SizedBox(height: 12),
          _buildAnalysisCard(report),
          SizedBox(height: 12),
          if (report.targets.isNotEmpty) ...[
            _buildTargetsCard(report),
            SizedBox(height: 12),
          ],
          Text('Санал болгосон үйлдлүүд',
              style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 4),
          if (report.suggestions.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Одоогоор өөрчлөх шаардлагагүй байна.'),
            ),
          ...report.suggestions.map(_buildSuggestionCard),
          SizedBox(height: 12),
          _buildModelInfo(report.modelMetrics, report.signalsDate),
          SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(Icons.refresh),
            label: Text('Дахин эхлүүлэх'),
            onPressed: advisor.reset,
          ),
          SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(Icons.flag_outlined),
            label: Text('Зорилгын төлөвлөгөө (N жилд X₮)'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GoalPlannerScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCard(AdvisorReport report) {
    final h = report.health;
    final color = h.score >= 70
        ? Colors.green
        : h.score >= 45
            ? Colors.orange
            : Colors.red;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: h.score / 100,
                    strokeWidth: 8,
                    color: color,
                    backgroundColor: color.withOpacity(0.15),
                  ),
                  Center(
                    child: Text('${h.score}',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                ],
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Багцын эрүүл мэнд',
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 6),
                  Text('Нийт үнэлгээ: ${_money.format(report.totalValue)}₮'),
                  Text('Профайл: ${report.profile.label}'),
                  Text('Жилийн хэлбэлзэл: ${(h.annualVol * 100).toStringAsFixed(0)}%'
                      ' · Бэлэн мөнгө: ${(h.cashWeight * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisCard(AdvisorReport report) {
    final h = report.health;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Багцын шинжилгээ',
                style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 8),
            Text(report.overview),
            if (h.strengths.isNotEmpty) ...[
              SizedBox(height: 16),
              Text('Давуу тал', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 4),
              ...h.strengths.map((s) => _buildAnalysisItem(s, true)),
            ],
            if (h.weaknesses.isNotEmpty) ...[
              SizedBox(height: 16),
              Text('Сайжруулах шаардлагатай',
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 4),
              ...h.weaknesses.map((s) => _buildAnalysisItem(s, false)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisItem(String text, bool positive) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(positive ? Icons.arrow_circle_up : Icons.arrow_circle_down,
              color: positive ? Colors.green : Colors.orange, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildTargetsCard(AdvisorReport report) {
    final cash = 1 - report.targets.fold<double>(0, (a, t) => a + t.weight);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Зорилтот хуваарилалт',
                style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 8),
            for (final t in report.targets)
              InkWell(
                onTap: () => _showExplanation(t.symbol, t.name),
                child: Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${t.symbol} · ${t.name}',
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('${(t.weight * 100).toStringAsFixed(1)}%',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SizedBox(height: 4),
                    LinearProgressIndicator(value: t.weight, minHeight: 6),
                    Text(
                      'Өсөх магадлал ${(t.signal.probUp * 100).toStringAsFixed(0)}% · '
                      'хэлбэлзэл ${(t.signal.annualVol * 100).toStringAsFixed(0)}% · '
                      'яагаад? →',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              ),
            Divider(),
            Row(
              children: [
                Expanded(child: Text('Бэлэн мөнгө')),
                Text('${(cash * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Загвар энэ хувьцааг яагаад сонгосныг харуулна.
  void _showExplanation(String symbol, String name) {
    final signals = context.read<AdvisorProvider>().signals;
    final signal = signals?.signalFor(symbol);
    if (signals == null || signal == null) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$symbol · $name',
                  style: Theme.of(ctx).textTheme.titleLarge),
              SizedBox(height: 12),
              SignalExplanation(
                signal: signal,
                baseRate: AdvisorEngine(signals).baseRate,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(Suggestion s) {
    late IconData icon;
    late Color color;
    switch (s.type) {
      case SuggestionType.buy:
        icon = Icons.add_circle_outline;
        color = Colors.green;
      case SuggestionType.sell:
        icon = Icons.remove_circle_outline;
        color = Colors.red;
      case SuggestionType.hold:
        icon = Icons.pause_circle_outline;
        color = Colors.blue;
      case SuggestionType.allocate:
        icon = Icons.pie_chart_outline;
        color = Colors.purple;
    }
    final canTrade = (s.type == SuggestionType.buy ||
            s.type == SuggestionType.sell) &&
        s.shares >= 1;

    return Card(
      margin: EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.15),
                  child: Icon(icon, color: color),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.action,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text('Шалтгаан:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text(s.reasoning),
            if (canTrade) ...[
              SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  icon: Icon(s.type == SuggestionType.buy
                      ? Icons.shopping_cart
                      : Icons.sell),
                  label: Text(s.type == SuggestionType.buy ? 'Авах' : 'Зарах'),
                  onPressed: () => _executeSuggestion(s),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Зөвлөгөөг симуляцийн данс дээр гүйцэтгэх (хэрэглэгч баталгаажуулна).
  Future<void> _executeSuggestion(Suggestion s) async {
    final isBuy = s.type == SuggestionType.buy;
    final price = s.amount / s.shares;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBuy ? 'Худалдан авах уу?' : 'Зарах уу?'),
        content: Text(
          '${s.symbol}: ${s.shares.toStringAsFixed(0)} ширхэг × '
          '${_money.format(price)}₮ = ${_money.format(s.amount)}₮\n\n'
          'Энэ нь симуляцийн дансны гүйлгээ.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Цуцлах')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isBuy ? 'Авах' : 'Зарах')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final portfolio = context.read<PortfolioProvider>();
    final success = isBuy
        ? await portfolio.buyStock(s.symbol, s.shares, price)
        : await portfolio.sellStock(s.symbol, s.shares, price);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Гүйлгээ амжилттай' : 'Гүйлгээ амжилтгүй'),
      backgroundColor: success ? Colors.green : Colors.red,
    ));
    if (success) await _generate();
  }

  /// Дохио хэр шинэ вэ (өдөр бүр серверээс шинэчлэгддэг).
  Widget _buildFreshness() {
    final advisor = context.watch<AdvisorProvider>();
    final date = advisor.dataDate;
    const sources = {
      SignalsSource.remote: 'серверээс шинэчилсэн',
      SignalsSource.cache: 'утсанд хадгалсан',
      SignalsSource.bundled: 'апп доторх',
    };
    final days = date == null ? null : DateTime.now().difference(date).inDays;
    final stale = advisor.isStale;
    final color = stale ? Colors.orange.shade800 : Colors.green.shade700;

    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(stale ? Icons.warning_amber : Icons.check_circle,
              size: 16, color: color),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              date == null
                  ? 'Дохио алга'
                  : 'Дохио: ${DateFormat('yyyy-MM-dd').format(date)}-ны арилжаагаар '
                      '(${sources[advisor.source] ?? ''})'
                      '${stale ? ' — $days хоногийн өмнөх, шинэчлэх шаардлагатай' : ''}',
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
          if (advisor.isRefreshing)
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (stale)
            IconButton(
              tooltip: 'Шинэ дохио татах',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.refresh, size: 18),
              onPressed: () => advisor.refreshRemote(force: true),
            ),
        ],
      ),
    );
  }

  Widget _buildModelInfo(Map<String, dynamic> m, DateTime generatedAt) {
    final bt = m['backtest'] as Map? ?? {};
    String pct(dynamic v) =>
        v is num ? '${(v * 100).toStringAsFixed(1)}%' : '—';
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory, size: 18),
                SizedBox(width: 8),
                Text('Загварын мэдээлэл',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            SizedBox(height: 8),
            _buildFreshness(),
            Text(
              'Өөрсдийн сургасан логистик регресс · ${m['stocks'] ?? '—'} хувьцаа, '
              '${m['samples'] ?? '—'} жишээ · тооцоолсон: '
              '${DateFormat('yyyy-MM-dd HH:mm').format(generatedAt)}',
              style: TextStyle(fontSize: 12),
            ),
            Text(
              'Тест AUC ${m['testAuc'] ?? '—'} · нарийвчлал ${pct(m['testAccuracy'])} '
              '(суурь ${pct(m['baselineAccuracy'])})',
              style: TextStyle(fontSize: 12),
            ),
            if (bt.isNotEmpty)
              Text(
                'Backtest ${bt['months']} сар: стратеги ${pct(bt['strategyTotalReturn'])}, '
                'жишиг ${pct(bt['benchmarkTotalReturn'])} (шимтгэлгүй)',
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

  Widget _errorBox(String text) => Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(color: Colors.red))),
          ],
        ),
      );
}

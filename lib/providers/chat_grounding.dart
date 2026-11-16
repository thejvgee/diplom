import '../ai_engine/advisor_engine.dart';
import '../ai_engine/chat_context.dart';
import '../ai_engine/risk_profile.dart';
import 'advisor_provider.dart';
import 'mse_market_provider.dart';
import 'portfolio_provider.dart';
import 'user_preferences_provider.dart';

/// GeminiService-д апп-ын бодит өгөгдлийг (багц, AI дохио, ханш) холбоно.
class ChatGrounding {
  final AdvisorProvider advisor;
  final PortfolioProvider portfolio;
  final UserPreferencesProvider preferences;
  final MseMarketProvider mse;

  ChatGrounding({
    required this.advisor,
    required this.portfolio,
    required this.preferences,
    required this.mse,
  });

  RiskProfile get _profile => RiskProfile.fromKey(preferences.riskTolerance);

  List<HoldingInput> get _holdings => [
        for (final h in portfolio.holdings)
          HoldingInput(
            symbol: h.symbol,
            quantity: h.quantity,
            averageCost: h.averageCost,
            currentPrice: h.currentPrice,
          ),
      ];

  AdvisorReport? _report() {
    final signals = advisor.signals;
    if (signals == null) return null;
    return AdvisorEngine(signals).analyze(
      holdings: _holdings,
      cash: portfolio.cashBalance,
      profile: _profile,
      livePrices: mse.lastPrices,
    );
  }

  /// Gemini-д өгөх контекст.
  String context() => ChatContext.build(
        signals: advisor.signals,
        report: _report(),
        holdings: _holdings,
        cash: portfolio.cashBalance,
        profile: _profile,
        livePrices: mse.lastPrices,
      );

  /// "X төгрөгөө юунд оруулах вэ" → Gemini-гүйгээр engine хариулна.
  String? localAnswer(String message) {
    final amount = ChatContext.investAmount(message);
    final signals = advisor.signals;
    if (amount == null || signals == null) return null;
    return ChatContext.investmentPlan(
      engine: AdvisorEngine(signals),
      amount: amount,
      profile: _profile,
      livePrices: mse.lastPrices,
    );
  }

  /// Gemini холбогдохгүй үеийн хариулт.
  String offlineAnswer(String message) =>
      ChatContext.offlineSummary(report: _report(), signals: advisor.signals);
}

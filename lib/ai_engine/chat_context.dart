import 'dart:math' as math;

import 'advisor_engine.dart';
import 'risk_profile.dart';
import 'signals.dart';

/// AI чатыг апп-ын бодит өгөгдөлд тулгуурлуулах туслах функцууд.
/// Gemini хувьцаа, ханш "зохиохоос" (hallucination) сэргийлнэ.
class ChatContext {
  /// Тэмдэглэгээ: энэ хариултыг Gemini биш, апп-ын AI загвар гаргасан.
  static const String localTag = '— Апп-ын AI загвар (MSE-ийн бодит өгөгдөл)';

  static final RegExp _investIntent = RegExp(
    r'(хөрөнгө\s*оруул|багц\s*бүрдүүл|хувьцаа\s*ав|юунд\s*оруул|хаана\s*оруул|'
    r'юу\s*авах|хуваарил|invest)',
    caseSensitive: false,
  );

  /// Мессежээс төгрөгийн дүн уншина: "100'000'000", "100,000,000",
  /// "10 сая", "1.5 сая", "500 мянга", "2 тэрбум", "5m". Олдохгүй бол null.
  static double? parseAmountMnt(String text) {
    var t = text.toLowerCase();
    // мянгатын тусгаарлагч (', ’, ,, хоосон зай) — ард нь 3 орон байвал
    t = t.replaceAllMapped(
        RegExp(r"(\d)['’, ](?=\d{3}(\D|$))"), (m) => m.group(1)!);
    t = t.replaceAllMapped(
        RegExp(r"(\d)['’, ](?=\d{3}(\D|$))"), (m) => m.group(1)!);
    double? best;
    for (final m in RegExp(r'(\d+(?:\.\d+)?)\s*(тэрбум|сая|мянга|мянган|k|m)?')
        .allMatches(t)) {
      final v = double.tryParse(m.group(1)!);
      if (v == null) continue;
      final mult = switch (m.group(2)) {
        'тэрбум' => 1e9,
        'сая' || 'm' => 1e6,
        'мянга' || 'мянган' || 'k' => 1e3,
        _ => 1.0,
      };
      final amount = v * mult;
      if (best == null || amount > best) best = amount;
    }
    return best;
  }

  /// "X төгрөгөө юунд хөрөнгө оруулах вэ" төрлийн асуулт уу.
  static double? investAmount(String text) {
    if (!_investIntent.hasMatch(text)) return null;
    final amount = parseAmountMnt(text);
    return amount != null && amount >= 10000 ? amount : null;
  }

  /// Тодорхой дүнг профайлаар хуваарилах санал — бүхэлдээ манай engine-ээр.
  static String investmentPlan({
    required AdvisorEngine engine,
    required double amount,
    required RiskProfile profile,
    Map<String, double> livePrices = const {},
  }) {
    final report = engine.analyze(
      holdings: const [],
      cash: amount,
      profile: profile,
      livePrices: livePrices,
    );
    final b = StringBuffer()
      ..writeln('${_money(amount)}₮-ийг **${profile.label}** профайлаар '
          'хуваарилах санал (MSE-ийн ${_date(report.signalsDate)}-ны өгөгдлөөр):')
      ..writeln();
    if (report.targets.isEmpty) {
      b.writeln('Одоогоор таны профайлын шалгуурыг хангасан, дунджаас сайн '
          'дохиотой хувьцаа алга. Бэлэн мөнгө/хадгаламжаар хүлээх нь зүйтэй.');
    }
    var i = 0;
    var invested = 0.0;
    for (final t in report.targets) {
      i++;
      final buy = report.suggestions.where(
          (s) => s.symbol == t.symbol && s.type == SuggestionType.buy);
      final shares = buy.isEmpty ? 0.0 : buy.first.shares;
      final spend = buy.isEmpty ? t.weight * amount : buy.first.amount;
      invested += spend;
      final price = shares > 0 ? spend / shares : t.signal.price;
      b.writeln('$i. **${t.symbol}** (${t.name}) — ${_pct(t.weight)} ≈ '
          '${_money(spend)}₮'
          '${shares > 0 ? ' → ${_money(shares)} ширхэг × ${_money(price)}₮' : ''}');
      b.writeln('   Өсөх магадлал ${_pct(t.signal.probUp)} '
          '(дунджаас ${_signed((engine.edgeOf(t.signal)) * 100)} пункт), '
          'жилийн хэлбэлзэл ${_pct(t.signal.annualVol)}');
    }
    b
      ..writeln()
      ..writeln('Бэлэн мөнгө/хадгаламж: ≈ ${_money(math.max(0, amount - invested))}₮ '
          '(${profile.label} профайлд ${_pct(profile.targetCash)} орчим байлгана).')
      ..writeln()
      ..writeln('Хувьцаа бүрийн "яагаад"-ыг Зах зээл → хувьцаан дээр дарж '
          '"AI шинжилгээ" хэсгээс харна уу.')
      ..writeln()
      ..writeln(AdvisorEngine.disclaimer)
      ..write(localTag);
    return b.toString();
  }

  /// Gemini-д өгөх контекст: хэрэглэгчийн багц, AI дохио, дүрэм.
  static String build({
    required SignalSet? signals,
    required AdvisorReport? report,
    required List<HoldingInput> holdings,
    required double cash,
    required RiskProfile profile,
    Map<String, double> livePrices = const {},
  }) {
    final engine = signals == null ? null : AdvisorEngine(signals);
    final b = StringBuffer()
      ..writeln('[АПП-ЫН БОДИТ ӨГӨГДӨЛ]')
      ..writeln('Хэрэглэгчийн эрсдэлийн профайл: ${profile.label}.');

    final value = holdings.fold<double>(0, (s, h) {
      final p = livePrices[h.symbol] ??
          (h.currentPrice > 0 ? h.currentPrice : h.averageCost);
      return s + h.quantity * p;
    });
    final total = value + cash;
    b.writeln('Симуляцийн багц: нийт ${_money(total)}₮, бэлэн мөнгө '
        '${_money(cash)}₮ (${total > 0 ? _pct(cash / total) : '—'}).');
    if (holdings.isEmpty) {
      b.writeln('Эзэмшиж буй хувьцаа алга.');
    } else {
      b.writeln('Эзэмшиж буй хувьцаа:');
      for (final h in holdings) {
        final p = livePrices[h.symbol] ??
            (h.currentPrice > 0 ? h.currentPrice : h.averageCost);
        final pl = h.averageCost > 0 ? p / h.averageCost - 1 : 0.0;
        final sig = signals?.signalFor(h.symbol);
        b.writeln('- ${h.symbol}: ${_money(h.quantity)} ширхэг, дундаж өртөг '
            '${_money(h.averageCost)}₮, одоо ${_money(p)}₮ (${_signed(pl * 100)}%)'
            '${sig == null ? '' : ', AI өсөх магадлал ${_pct(sig.probUp)}'}');
      }
    }
    if (report != null) {
      b.writeln('Багцын эрүүл мэнд: ${report.health.score}/100.');
      for (final w in report.health.weaknesses) {
        b.writeln('  Сул тал: $w');
      }
    }
    if (signals != null && engine != null) {
      final top = signals.signals
          .where((s) => s.liquidity >= 0.6 && engine.edgeOf(s) > 0.02)
          .toList()
        ..sort((a, c) => engine.edgeOf(c).compareTo(engine.edgeOf(a)));
      b
        ..writeln('AI загварын (логистик регресс, MSE ${_date(signals.generatedAt)}) '
            'хамгийн сайн дохиотой, идэвхтэй арилжаалагддаг хувьцаа '
            '(30 хоногт өсөх магадлал; зах зээлийн дундаж ${_pct(engine.baseRate)}):');
      for (final s in top.take(8)) {
        b.writeln('- ${s.symbol} (${s.name}): ${_pct(s.probUp)}, жилийн '
            'хэлбэлзэл ${_pct(s.annualVol)}, 60 өдрийн өгөөж ${_signed(s.ret60 * 100)}%');
      }
      final market = signals.modelMetrics['market'];
      if (market is Map && market['annualReturn'] is num) {
        b.writeln('MSE-ийн сүүлийн ${market['months']} сарын тэнцүү жинтэй '
            'жилийн дундаж өгөөж: ${_pct((market['annualReturn'] as num).toDouble())}.');
      }
    }
    b
      ..writeln()
      ..writeln('ДҮРЭМ: Хувьцаа, ханш, магадлал, хэрэглэгчийн багцын талаар ЗӨВХӨН '
          'дээрх өгөгдлийг ашигла. Энд байхгүй хувьцаа санал болгохгүй, тоо '
          'зохиохгүй; мэдэхгүй бол "апп-д энэ мэдээлэл алга" гэж хэл. Ерөнхий '
          'санхүүгийн ойлголтыг тайлбарлаж болно. Монгол хэлээр, товч хариул.');
    return b.toString();
  }

  /// Gemini холбогдохгүй үед: багцын бодит тойм.
  static String offlineSummary({
    required AdvisorReport? report,
    required SignalSet? signals,
  }) {
    if (report == null || signals == null) {
      return 'Багцын шинжилгээг "Санал болгох багц" хэсгээс харна уу.';
    }
    final engine = AdvisorEngine(signals);
    final top = report.targets.take(3).map((t) =>
        '${t.symbol} (${_pct(t.signal.probUp)}, дунджаас '
        '${_signed(engine.edgeOf(t.signal) * 100)} пункт)');
    final b = StringBuffer()
      ..writeln('Таны багцын тойм (апп-ын AI загвараар):')
      ..writeln('• Эрүүл мэндийн оноо: ${report.health.score}/100')
      ..writeln('• Нийт үнэлгээ: ${_money(report.totalValue)}₮');
    for (final w in report.health.weaknesses.take(2)) {
      b.writeln('• $w');
    }
    if (top.isNotEmpty) {
      b.writeln('• ${report.profile.label} профайлд тохирох: ${top.join(', ')}');
    }
    b.write(localTag);
    return b.toString();
  }

  static String _money(double v) {
    final s = v.round().abs().toString();
    final out = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  static String _pct(double v) => '${(v * 100).toStringAsFixed(v.abs() < 0.1 ? 1 : 0)}%';
  static String _signed(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';
  static String _date(DateTime d) => d.toIso8601String().substring(0, 10);
}

// AI зөвлөхийг терминал дээр туршиж харах (хамгаалалтад үзүүлэхэд тохиромжтой).
//   dart run tool/advisor_demo.dart [Conservative|Moderate|Aggressive|...]
import 'dart:convert';
import 'dart:io';

import 'package:jvgee_diplom/ai_engine/advisor_engine.dart';
import 'package:jvgee_diplom/ai_engine/risk_profile.dart';
import 'package:jvgee_diplom/ai_engine/signals.dart';

void main(List<String> args) {
  final set = SignalSet.fromJson(
      jsonDecode(File('assets/ai/signals.json').readAsStringSync()) as Map<String, dynamic>);
  final profile = RiskProfile.fromKey(args.isEmpty ? 'Moderate' : args.first);

  // Апп-ын жишээ багц (PortfolioProvider.addSampleHoldings) + 10 сая бэлэн мөнгө
  final holdings = [
    HoldingInput(symbol: 'AARD', quantity: 10, averageCost: 2450),
    HoldingInput(symbol: 'ADB', quantity: 10, averageCost: 100),
    HoldingInput(symbol: 'APU', quantity: 10, averageCost: 978.85),
    HoldingInput(symbol: 'BODI', quantity: 10, averageCost: 82),
    HoldingInput(symbol: 'SUU', quantity: 10, averageCost: 619.62),
    HoldingInput(symbol: 'GLMT', quantity: 8, averageCost: 1044),
  ];
  final r = AdvisorEngine(set).analyze(holdings: holdings, cash: 1e7, profile: profile);

  stdout.writeln('== ${profile.label} профайл ==');
  stdout.writeln(r.overview);
  stdout.writeln('Оноо ${r.health.score}/100, хэлбэлзэл ${(r.health.annualVol * 100).toStringAsFixed(1)}%');
  for (final s in r.health.strengths) {
    stdout.writeln('  + $s');
  }
  for (final s in r.health.weaknesses) {
    stdout.writeln('  - $s');
  }
  stdout.writeln('\nЗорилтот хуваарилалт:');
  for (final t in r.targets) {
    stdout.writeln('  ${t.symbol.padRight(5)} ${(t.weight * 100).toStringAsFixed(1).padLeft(5)}%  '
        'p=${t.signal.probUp.toStringAsFixed(3)} vol=${(t.signal.annualVol * 100).toStringAsFixed(0)}% '
        'liq=${t.signal.liquidity.toStringAsFixed(2)}');
  }
  stdout.writeln('\nЗөвлөгөө:');
  for (final s in r.suggestions) {
    stdout.writeln('  [${s.type.name}] ${s.action}\n      ${s.reasoning}');
  }
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jvgee_diplom/ai_engine/goal_planner.dart';

void main() {
  const noRisk = MarketAssumptions(
    stockMonthlyMean: 0,
    stockMonthlyVol: 1e-9,
    cashAnnualRate: 0,
  );

  test('эрсдэлгүй, өгөөжгүй үед шаардлагатай хуримтлал = зорилго / сар', () {
    final plan = GoalPlanner(noRisk, paths: 200)
        .plan(target: 12000000, years: 1, initial: 0, stockShare: 0);
    expect(plan.requiredMonthly(0.5), closeTo(1000000, 1));
    expect(plan.probability(1000001), 1.0);
    expect(plan.probability(999000), 0.0);
  });

  test('хадгаламжийн хүүтэй үед нийлмэл хүүгээр тооцно', () {
    const cash = MarketAssumptions(
        stockMonthlyMean: 0, stockMonthlyVol: 1e-9, cashAnnualRate: 0.12);
    final plan = GoalPlanner(cash, paths: 50)
        .plan(target: 1, years: 2, initial: 1000000, stockShare: 0);
    final median = plan.bands(0, percentiles: [0.5]).first;
    expect(median[2], closeTo(1000000 * math.pow(1.12, 2), 1));
  });

  test('эхний мөнгө хангалттай бол нэмэлт хуримтлал шаардлагагүй', () {
    final plan = GoalPlanner(noRisk, paths: 100)
        .plan(target: 5e6, years: 3, initial: 6e6, stockShare: 0);
    expect(plan.requiredMonthly(0.9), 0);
    expect(plan.probability(0), 1.0);
  });

  test('өндөр магадлал = их хуримтлал, магадлал хуримтлалаар өснө', () {
    final a = MarketAssumptions.fromMetrics(
        {'monthlyMean': 0.008, 'monthlyVol': 0.03, 'since': '2016-11', 'months': 120});
    final plan = GoalPlanner(a).plan(
        target: 20e6, years: 3, initial: 2e6, stockShare: 0.8);
    final c50 = plan.requiredMonthly(0.5);
    final c80 = plan.requiredMonthly(0.8);
    expect(c80, greaterThan(c50));
    expect(plan.probability(c50), closeTo(0.5, 0.02));
    expect(plan.probability(c80), closeTo(0.8, 0.02));
    expect(plan.probability(c80 * 2), greaterThan(plan.probability(c80)));
    // Хэлбэлзлийн доод хязгаар (20%) хэрэгжсэн
    expect(a.stockAnnualVol, closeTo(0.20, 1e-9));
    final b = plan.bands(c80);
    expect(b[0].last, lessThan(b[1].last));
    expect(b[1].last, lessThan(b[2].last));
  });

  test('ижил seed → ижил үр дүн', () {
    final a = MarketAssumptions.fromMetrics(null);
    final p1 = GoalPlanner(a).plan(target: 1e7, years: 5, initial: 0, stockShare: 0.5);
    final p2 = GoalPlanner(a).plan(target: 1e7, years: 5, initial: 0, stockShare: 0.5);
    expect(p1.requiredMonthly(0.8), p2.requiredMonthly(0.8));
  });
}

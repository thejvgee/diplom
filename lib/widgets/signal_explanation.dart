import 'package:flutter/material.dart';

import '../ai_engine/advisor_engine.dart';
import '../ai_engine/signals.dart';

/// AI загвар яагаад ийм дүгнэлт гаргасныг харуулна: шинж бүр өсөх
/// магадлалыг хэр өсгөсөн (ногоон) эсвэл бууруулсан (улаан).
///
/// Утга = логистик регрессийн жин × стандартчилсан шинж (log-odds-ийн нөлөө).
class SignalExplanation extends StatelessWidget {
  final StockSignal signal;
  final double baseRate;
  final int maxRows;

  const SignalExplanation({
    super.key,
    required this.signal,
    required this.baseRate,
    this.maxRows = 11,
  });

  @override
  Widget build(BuildContext context) {
    final edge = signal.probUp - baseRate;
    final positive = edge > 0.02;
    final negative = edge < -0.03;
    final verdictColor = positive
        ? Colors.green.shade700
        : negative
            ? Colors.red.shade700
            : Colors.orange.shade800;
    final verdict = positive
        ? 'Дунджаас сайн'
        : negative
            ? 'Дунджаас сул'
            : 'Төвийг сахисан';

    final drivers = signal.drivers.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final rows = drivers.take(maxRows).toList();
    final maxAbs = rows.isEmpty
        ? 1.0
        : rows.map((e) => e.value.abs()).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.psychology, size: 20, color: verdictColor),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '30 хоногт өсөх магадлал ${(signal.probUp * 100).toStringAsFixed(1)}% '
                '(дундаж ${(baseRate * 100).toStringAsFixed(0)}%)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: verdictColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(verdict,
                  style: TextStyle(fontSize: 12, color: verdictColor)),
            ),
          ],
        ),
        SizedBox(height: 12),
        for (final e in rows) _bar(context, e.key, e.value, maxAbs),
        SizedBox(height: 6),
        Text(
          'Ногоон — магадлалыг өсгөсөн, улаан — бууруулсан. '
          'Урт зураас = их нөлөө.',
          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, String name, double value, double maxAbs) {
    final featureValue = signal.features[name];
    final label = featureValue == null
        ? name
        : AdvisorEngine.describeFeature(name, featureValue);
    final frac = maxAbs <= 0 ? 0.0 : (value.abs() / maxAbs).clamp(0.0, 1.0);
    final color = value >= 0 ? Colors.green : Colors.red;
    final track = Theme.of(context).dividerColor.withValues(alpha: 0.3);

    Widget half(bool active, Alignment align) => Expanded(
          child: Container(
            height: 10,
            color: track,
            alignment: align,
            child: active
                ? FractionallySizedBox(
                    widthFactor: frac,
                    child: Container(color: color),
                  )
                : null,
          ),
        );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12)),
          SizedBox(height: 2),
          Row(
            children: [
              half(value < 0, Alignment.centerRight),
              Container(width: 1, height: 14, color: Colors.grey),
              half(value >= 0, Alignment.centerLeft),
            ],
          ),
        ],
      ),
    );
  }
}

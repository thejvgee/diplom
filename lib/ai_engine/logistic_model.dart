import 'dart:math' as math;

/// Өөрсдөө бичсэн логистик регресс (binary classification).
///
/// Зорилго: "дараагийн 30 хоногт хувьцааны ханш өсөх магадлал".
/// Гадны сан ашиглахгүй — сургалт ч, таамаглал ч цэвэр Dart.
class LogisticModel {
  final List<String> featureNames;
  final List<double> means;
  final List<double> stds;
  final List<double> weights;
  final double bias;

  /// Сургалт, тестийн үзүүлэлтүүд (JSON-д хамт хадгална).
  final Map<String, dynamic> metrics;

  const LogisticModel({
    required this.featureNames,
    required this.means,
    required this.stds,
    required this.weights,
    required this.bias,
    this.metrics = const {},
  });

  /// Ханш өсөх магадлал (0..1).
  double predict(List<double> x) {
    var z = bias;
    for (var k = 0; k < weights.length; k++) {
      z += weights[k] * ((x[k] - means[k]) / stds[k]);
    }
    return 1 / (1 + math.exp(-z.clamp(-30.0, 30.0)));
  }

  /// Шинж бүр таамаглалд хэрхэн нөлөөлснийг (стандартчилсан утга × жин)
  /// буцаана — зөвлөгөөг тайлбарлахад ашиглана.
  Map<String, double> contributions(List<double> x) => {
        for (var k = 0; k < weights.length; k++)
          featureNames[k]: weights[k] * ((x[k] - means[k]) / stds[k]),
      };

  /// Batch gradient descent + L2 регуляризаци.
  static LogisticModel train(
    List<List<double>> xs,
    List<int> ys, {
    required List<String> featureNames,
    int epochs = 400,
    double learningRate = 0.5,
    double l2 = 1e-3,
  }) {
    final n = xs.length;
    final d = featureNames.length;
    if (n == 0) throw ArgumentError('Сургалтын өгөгдөл хоосон');

    // Стандартчилах (mean = 0, std = 1)
    final means = List<double>.filled(d, 0);
    final stds = List<double>.filled(d, 0);
    for (final x in xs) {
      for (var k = 0; k < d; k++) {
        means[k] += x[k] / n;
      }
    }
    for (final x in xs) {
      for (var k = 0; k < d; k++) {
        stds[k] += (x[k] - means[k]) * (x[k] - means[k]) / n;
      }
    }
    for (var k = 0; k < d; k++) {
      stds[k] = math.sqrt(stds[k]);
      if (stds[k] < 1e-12) stds[k] = 1;
    }
    final z = [
      for (final x in xs) [for (var k = 0; k < d; k++) (x[k] - means[k]) / stds[k]]
    ];

    final w = List<double>.filled(d, 0);
    final positives = ys.where((y) => y == 1).length;
    var b = math.log((positives + 1) / (n - positives + 1));

    for (var epoch = 0; epoch < epochs; epoch++) {
      final gw = List<double>.filled(d, 0);
      var gb = 0.0;
      for (var i = 0; i < n; i++) {
        var s = b;
        for (var k = 0; k < d; k++) {
          s += w[k] * z[i][k];
        }
        final p = 1 / (1 + math.exp(-s.clamp(-30.0, 30.0)));
        final err = p - ys[i];
        for (var k = 0; k < d; k++) {
          gw[k] += err * z[i][k];
        }
        gb += err;
      }
      for (var k = 0; k < d; k++) {
        w[k] -= learningRate * (gw[k] / n + l2 * w[k]);
      }
      b -= learningRate * gb / n;
    }

    return LogisticModel(
      featureNames: featureNames,
      means: means,
      stds: stds,
      weights: w,
      bias: b,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'logistic_regression',
        'features': featureNames,
        'means': means,
        'stds': stds,
        'weights': weights,
        'bias': bias,
        'metrics': metrics,
      };

  factory LogisticModel.fromJson(Map<String, dynamic> json) => LogisticModel(
        featureNames: List<String>.from(json['features'] as List),
        means: _doubles(json['means']),
        stds: _doubles(json['stds']),
        weights: _doubles(json['weights']),
        bias: (json['bias'] as num).toDouble(),
        metrics: Map<String, dynamic>.from(json['metrics'] as Map? ?? {}),
      );

  LogisticModel withMetrics(Map<String, dynamic> m) => LogisticModel(
        featureNames: featureNames,
        means: means,
        stds: stds,
        weights: weights,
        bias: bias,
        metrics: m,
      );

  static List<double> _doubles(dynamic v) =>
      [for (final x in v as List) (x as num).toDouble()];
}

/// ROC AUC — ангилагчийн чанарыг хэмжих (0.5 = санамсаргүй таамаг).
double rocAuc(List<double> scores, List<int> labels) {
  final idx = List<int>.generate(scores.length, (i) => i)
    ..sort((a, b) => scores[a].compareTo(scores[b]));
  final pos = labels.where((y) => y == 1).length;
  final neg = labels.length - pos;
  if (pos == 0 || neg == 0) return 0.5;
  // Ижил онооны зэрэглэлийг дундажлана
  var rankSum = 0.0;
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && scores[idx[j + 1]] == scores[idx[i]]) {
      j++;
    }
    final avgRank = (i + j) / 2 + 1;
    for (var k = i; k <= j; k++) {
      if (labels[idx[k]] == 1) rankSum += avgRank;
    }
    i = j + 1;
  }
  return (rankSum - pos * (pos + 1) / 2) / (pos * neg);
}

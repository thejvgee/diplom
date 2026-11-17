import 'dart:math' as math;

/// Дохионы загваруудын нийтлэг интерфэйс (логистик регресс, GBM).
abstract class SignalModel {
  List<String> get featureNames;

  /// Log-odds (logit) утга.
  double margin(List<double> x);

  /// Шинж бүрийн нөлөө (log-odds). Нийлбэр + суурь = [margin].
  Map<String, double> contributions(List<double> x);

  Map<String, dynamic> toJson();

  double predict(List<double> x) => sigmoid(margin(x));
}

double sigmoid(double z) => 1 / (1 + math.exp(-z.clamp(-30.0, 30.0)));

/// Өөрсдөө бичсэн логистик регресс (Ньютоны арга / IRLS + L2).
/// Гадны сан ашиглахгүй — сургалт ч, таамаглал ч цэвэр Dart.
class LogisticModel extends SignalModel {
  @override
  final List<String> featureNames;
  final List<double> means;
  final List<double> stds;
  final List<double> weights;
  final double bias;

  /// Сургалт, тестийн үзүүлэлтүүд (JSON-д хамт хадгална).
  final Map<String, dynamic> metrics;

  LogisticModel({
    required this.featureNames,
    required this.means,
    required this.stds,
    required this.weights,
    required this.bias,
    this.metrics = const {},
  });

  double _z(List<double> x, int k) => (x[k] - means[k]) / stds[k];

  @override
  double margin(List<double> x) {
    var z = bias;
    for (var k = 0; k < weights.length; k++) {
      z += weights[k] * _z(x, k);
    }
    return z;
  }

  @override
  Map<String, double> contributions(List<double> x) => {
        for (var k = 0; k < weights.length; k++)
          featureNames[k]: weights[k] * _z(x, k),
      };

  /// Ньютоны арга: Hessian-ийг шууд шийдэж ~10 алхамд нийлнэ.
  static LogisticModel train(
    List<List<double>> xs,
    List<int> ys, {
    required List<String> featureNames,
    double l2 = 1e-3,
    int maxIter = 30,
  }) {
    final n = xs.length;
    final d = featureNames.length;
    if (n == 0) throw ArgumentError('Сургалтын өгөгдөл хоосон');

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
    // z[i] = [1, стандартчилсан шинжүүд...]
    final z = [
      for (final x in xs)
        [1.0, for (var k = 0; k < d; k++) (x[k] - means[k]) / stds[k]]
    ];
    final m = d + 1;
    final w = List<double>.filled(m, 0);
    final pos = ys.where((y) => y == 1).length;
    w[0] = math.log((pos + 1) / (n - pos + 1));

    for (var iter = 0; iter < maxIter; iter++) {
      final g = List<double>.filled(m, 0);
      final h = List.generate(m, (_) => List<double>.filled(m, 0));
      for (var i = 0; i < n; i++) {
        final zi = z[i];
        var s = 0.0;
        for (var k = 0; k < m; k++) {
          s += w[k] * zi[k];
        }
        final p = sigmoid(s);
        final err = p - ys[i];
        final wt = math.max(p * (1 - p), 1e-9);
        for (var a = 0; a < m; a++) {
          g[a] += err * zi[a];
          final wa = wt * zi[a];
          for (var b = a; b < m; b++) {
            h[a][b] += wa * zi[b];
          }
        }
      }
      for (var a = 0; a < m; a++) {
        g[a] = g[a] / n + (a == 0 ? 0 : l2 * w[a]);
        for (var b = a; b < m; b++) {
          h[a][b] = h[a][b] / n + (a == b && a > 0 ? l2 : 0);
          h[b][a] = h[a][b];
        }
      }
      final step = _solve(h, g);
      var maxStep = 0.0;
      for (var k = 0; k < m; k++) {
        w[k] -= step[k];
        maxStep = math.max(maxStep, step[k].abs());
      }
      if (maxStep < 1e-7) break;
    }

    return LogisticModel(
      featureNames: featureNames,
      means: means,
      stds: stds,
      weights: w.sublist(1),
      bias: w[0],
    );
  }

  /// Гауссын арга (тэнхлэг сонголттой) — A·x = b.
  static List<double> _solve(List<List<double>> a, List<double> b) {
    final n = b.length;
    final m = [for (var i = 0; i < n; i++) [...a[i], b[i]]];
    for (var col = 0; col < n; col++) {
      var piv = col;
      for (var r = col + 1; r < n; r++) {
        if (m[r][col].abs() > m[piv][col].abs()) piv = r;
      }
      final tmp = m[col];
      m[col] = m[piv];
      m[piv] = tmp;
      final p = m[col][col].abs() < 1e-12 ? 1e-12 : m[col][col];
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final f = m[r][col] / p;
        if (f == 0) continue;
        for (var k = col; k <= n; k++) {
          m[r][k] -= f * m[col][k];
        }
      }
    }
    return [for (var i = 0; i < n; i++) m[i][n] / (m[i][i].abs() < 1e-12 ? 1e-12 : m[i][i])];
  }

  @override
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

/// Platt-ийн тохируулга: p = σ(a·margin + b). Загварын "60%" гэдэг нь бодитоор
/// ~60% биелдэг болгоно. Загвар хараагүй (walk-forward) таамаг дээр сургана.
class PlattCalibration {
  final double a;
  final double b;
  const PlattCalibration(this.a, this.b);

  static const identity = PlattCalibration(1, 0);

  double apply(double margin) => sigmoid(a * margin + b);

  static PlattCalibration fit(List<double> margins, List<int> ys) {
    var a = 1.0, b = 0.0;
    for (var iter = 0; iter < 50; iter++) {
      var ga = 0.0, gb = 0.0, haa = 0.0, hab = 0.0, hbb = 0.0;
      for (var i = 0; i < margins.length; i++) {
        final p = sigmoid(a * margins[i] + b);
        final e = p - ys[i];
        final w = math.max(p * (1 - p), 1e-9);
        ga += e * margins[i];
        gb += e;
        haa += w * margins[i] * margins[i];
        hab += w * margins[i];
        hbb += w;
      }
      final det = haa * hbb - hab * hab;
      if (det.abs() < 1e-12) break;
      final da = (hbb * ga - hab * gb) / det;
      final db = (haa * gb - hab * ga) / det;
      a -= da;
      b -= db;
      if (da.abs() < 1e-9 && db.abs() < 1e-9) break;
    }
    return PlattCalibration(a, b);
  }

  Map<String, dynamic> toJson() => {'a': a, 'b': b};
}

/// ROC AUC — ангилагчийн чанарыг хэмжих (0.5 = санамсаргүй таамаг).
double rocAuc(List<double> scores, List<int> labels) {
  final idx = List<int>.generate(scores.length, (i) => i)
    ..sort((a, b) => scores[a].compareTo(scores[b]));
  final pos = labels.where((y) => y == 1).length;
  final neg = labels.length - pos;
  if (pos == 0 || neg == 0) return 0.5;
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

/// Спирменийн эрэмбийн корреляци (Rank IC).
double spearman(List<double> a, List<double> b) {
  List<double> ranks(List<double> v) {
    final idx = List<int>.generate(v.length, (i) => i)
      ..sort((x, y) => v[x].compareTo(v[y]));
    final r = List<double>.filled(v.length, 0);
    var i = 0;
    while (i < idx.length) {
      var j = i;
      while (j + 1 < idx.length && v[idx[j + 1]] == v[idx[i]]) {
        j++;
      }
      for (var k = i; k <= j; k++) {
        r[idx[k]] = (i + j) / 2;
      }
      i = j + 1;
    }
    return r;
  }

  final ra = ranks(a), rb = ranks(b);
  final n = a.length;
  if (n < 3) return 0;
  final ma = ra.reduce((x, y) => x + y) / n, mb = rb.reduce((x, y) => x + y) / n;
  var cov = 0.0, va = 0.0, vb = 0.0;
  for (var i = 0; i < n; i++) {
    cov += (ra[i] - ma) * (rb[i] - mb);
    va += (ra[i] - ma) * (ra[i] - ma);
    vb += (rb[i] - mb) * (rb[i] - mb);
  }
  return va == 0 || vb == 0 ? 0 : cov / math.sqrt(va * vb);
}

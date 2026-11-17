import 'dart:math' as math;
import 'dart:typed_data';

import 'logistic_model.dart';

/// Gradient Boosted Decision Trees (binary log-loss), өөрсдөө бичсэн.
///
/// * Histogram аргаар (шинж бүрийг ≤32 бүлэгт хувааж) хурдан сургана.
/// * Шийдвэрийн тайлбар: Saabas арга — модны зам дагуух утгын өөрчлөлтийг
///   хуваах шинжид оноож, нөлөөний нийлбэр + суурь = log-odds болно.
class GbmModel extends SignalModel {
  @override
  final List<String> featureNames;
  final double baseMargin;

  /// Мод бүр: зангилаа [feature, threshold, left, right, value]; feature<0 = навч.
  final List<List<List<double>>> trees;

  GbmModel({
    required this.featureNames,
    required this.baseMargin,
    required this.trees,
  });

  @override
  double margin(List<double> x) {
    var m = baseMargin;
    for (final t in trees) {
      var node = 0;
      while (t[node][0] >= 0) {
        final f = t[node][0].toInt();
        node = (x[f] <= t[node][1] ? t[node][2] : t[node][3]).toInt();
      }
      m += t[node][4];
    }
    return m;
  }

  @override
  Map<String, double> contributions(List<double> x) {
    final c = List<double>.filled(featureNames.length, 0);
    for (final t in trees) {
      var node = 0;
      while (t[node][0] >= 0) {
        final f = t[node][0].toInt();
        final next = (x[f] <= t[node][1] ? t[node][2] : t[node][3]).toInt();
        c[f] += t[next][4] - t[node][4];
        node = next;
      }
    }
    return {for (var k = 0; k < c.length; k++) featureNames[k]: c[k]};
  }

  /// Шинж бүрийн нийт ач холбогдол (хуваалтын тоо) — тайланд.
  Map<String, int> splitCounts() {
    final c = <String, int>{};
    for (final t in trees) {
      for (final n in t) {
        if (n[0] >= 0) {
          final name = featureNames[n[0].toInt()];
          c[name] = (c[name] ?? 0) + 1;
        }
      }
    }
    return c;
  }

  static GbmModel train(
    List<List<double>> xs,
    List<int> ys, {
    required List<String> featureNames,
    int nTrees = 150,
    int maxDepth = 3,
    double learningRate = 0.05,
    int minLeaf = 200,
    int bins = 32,
    double lambda = 1.0,
    double subsample = 0.8,
    int seed = 7,
  }) {
    final n = xs.length, d = featureNames.length;
    if (n == 0) throw ArgumentError('Сургалтын өгөгдөл хоосон');

    // 1. Шинж бүрийн квантилийн босгууд ба бүлгийн индекс
    final thresholds = <List<double>>[];
    final binned = <Uint8List>[];
    for (var k = 0; k < d; k++) {
      final vals = Float64List(n);
      for (var i = 0; i < n; i++) {
        vals[i] = xs[i][k];
      }
      final sorted = Float64List.fromList(vals)..sort();
      final th = <double>[];
      for (var b = 1; b < bins; b++) {
        final v = sorted[(b * (n - 1) / bins).floor()];
        if (th.isEmpty || v > th.last) th.add(v);
      }
      thresholds.add(th);
      final bk = Uint8List(n);
      for (var i = 0; i < n; i++) {
        var lo = 0, hi = th.length;
        while (lo < hi) {
          final mid = (lo + hi) >> 1;
          if (vals[i] <= th[mid]) {
            hi = mid;
          } else {
            lo = mid + 1;
          }
        }
        bk[i] = lo;
      }
      binned.add(bk);
    }

    final pos = ys.where((y) => y == 1).length;
    final base = math.log((pos + 1) / (n - pos + 1));
    final f = Float64List(n)..fillRange(0, n, base);
    final g = Float64List(n), h = Float64List(n);
    final rnd = math.Random(seed);
    final trees = <List<List<double>>>[];

    for (var t = 0; t < nTrees; t++) {
      for (var i = 0; i < n; i++) {
        final p = sigmoid(f[i]);
        g[i] = p - ys[i];
        h[i] = math.max(p * (1 - p), 1e-9);
      }
      final rows = <int>[
        for (var i = 0; i < n; i++)
          if (rnd.nextDouble() < subsample) i
      ];
      final nodes = <List<double>>[];
      // Зангилаа бүрийн мөрүүд (навчны утгыг бүх мөрөнд хэрэглэхэд бүлгийн
      // индексээр дахин хуваана).
      void build(Int32List idx, int depth, int nodeId) {
        var gs = 0.0, hs = 0.0;
        for (final i in idx) {
          gs += g[i];
          hs += h[i];
        }
        final value = -gs / (hs + lambda) * learningRate;
        nodes[nodeId] = [-1, 0, -1, -1, value];
        if (depth >= maxDepth || idx.length < 2 * minLeaf) return;

        final parentScore = gs * gs / (hs + lambda);
        var bestGain = 1e-6, bestF = -1, bestB = -1;
        for (var k = 0; k < d; k++) {
          final nb = thresholds[k].length + 1;
          final gh = Float64List(nb), hh = Float64List(nb);
          final cnt = Int32List(nb);
          final bk = binned[k];
          for (final i in idx) {
            final b = bk[i];
            gh[b] += g[i];
            hh[b] += h[i];
            cnt[b]++;
          }
          var gl = 0.0, hl = 0.0, cl = 0;
          for (var b = 0; b < nb - 1; b++) {
            gl += gh[b];
            hl += hh[b];
            cl += cnt[b];
            final cr = idx.length - cl;
            if (cl < minLeaf) continue;
            if (cr < minLeaf) break;
            final gr = gs - gl, hr = hs - hl;
            final gain = gl * gl / (hl + lambda) + gr * gr / (hr + lambda) - parentScore;
            if (gain > bestGain) {
              bestGain = gain;
              bestF = k;
              bestB = b;
            }
          }
        }
        if (bestF < 0) return;

        final bk = binned[bestF];
        final left = <int>[], right = <int>[];
        for (final i in idx) {
          (bk[i] <= bestB ? left : right).add(i);
        }
        final l = nodes.length;
        nodes.add([]);
        final r = nodes.length;
        nodes.add([]);
        nodes[nodeId] = [
          bestF.toDouble(),
          thresholds[bestF][bestB],
          l.toDouble(),
          r.toDouble(),
          value,
        ];
        build(Int32List.fromList(left), depth + 1, l);
        build(Int32List.fromList(right), depth + 1, r);
      }

      nodes.add([]);
      build(Int32List.fromList(rows), 0, 0);

      // Бүх мөрийн margin-ийг шинэчилнэ (бүлгийн индексээр — босготой ижил).
      for (var i = 0; i < n; i++) {
        var node = 0;
        while (nodes[node][0] >= 0) {
          final k = nodes[node][0].toInt();
          final thr = nodes[node][1];
          node = (xs[i][k] <= thr ? nodes[node][2] : nodes[node][3]).toInt();
        }
        f[i] += nodes[node][4];
      }
      trees.add(nodes);
    }

    return GbmModel(featureNames: featureNames, baseMargin: base, trees: trees);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'gbm',
        'features': featureNames,
        'base': baseMargin,
        'trees': [
          for (final t in trees)
            [
              for (final node in t)
                [for (final v in node) (v * 1e6).roundToDouble() / 1e6]
            ]
        ],
      };

  factory GbmModel.fromJson(Map<String, dynamic> j) => GbmModel(
        featureNames: List<String>.from(j['features'] as List),
        baseMargin: (j['base'] as num).toDouble(),
        trees: [
          for (final t in j['trees'] as List)
            [
              for (final node in t as List)
                [for (final v in node as List) (v as num).toDouble()]
            ]
        ],
      );
}

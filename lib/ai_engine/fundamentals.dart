/// Компанийн санхүүгийн тайлангийн үзүүлэлтүүд (open.mse.mn).
///
/// Сургалтад "ирээдүйн мэдээлэл" алдагдуулахгүйн тулд тайлан бүрийг
/// нийтлэгдсэн огнооноос нь хойш л ашиглана (point-in-time).
class FinancialReport {
  final int year;

  /// 4 = жилийн, 2 = хагас жилийн тайлан.
  final int season;

  /// Тайлан нийтлэгдсэн огноо (мэдэгдэхгүй бол таамагласан).
  final DateTime published;

  /// Нэгж хувьцааны цэвэр ашиг (EPS). 0 = мэдээлэлгүй.
  final double eps;

  /// Нэгж хувьцааны дансны үнэ (BVPS). 0 = мэдээлэлгүй.
  final double bvps;

  /// Өмчийн өгөөж (ROE, хувиар). null = мэдээлэлгүй.
  final double? roe;

  const FinancialReport({
    required this.year,
    required this.season,
    required this.published,
    required this.eps,
    required this.bvps,
    this.roe,
  });

  /// Нийтлэгдсэн огноо мэдэгдэхгүй үеийн болгоомжтой таамаг.
  static DateTime assumedPublication(int year, int season) => season >= 4
      ? DateTime(year + 1, 4, 30)
      : DateTime(year, season * 3 + 2, 15);

  Map<String, dynamic> toJson() => {
        'year': year,
        'season': season,
        'published': published.toIso8601String().substring(0, 10),
        'eps': eps,
        'bvps': bvps,
        'roe': roe,
      };

  factory FinancialReport.fromJson(Map<String, dynamic> j) => FinancialReport(
        year: j['year'] as int,
        season: j['season'] as int,
        published: DateTime.parse(j['published'] as String),
        eps: (j['eps'] as num).toDouble(),
        bvps: (j['bvps'] as num).toDouble(),
        roe: (j['roe'] as num?)?.toDouble(),
      );
}

/// Тухайн өдөр зах зээлд мэдэгдэж байсан үзүүлэлтүүд.
class FundamentalSnapshot {
  final double? eps; // сүүлийн жилийн тайлангийн EPS
  final double? bvps; // хамгийн сүүлийн тайлангийн BVPS
  final double? roe; // сүүлийн жилийн ROE (бутархай, 0.12 = 12%)
  const FundamentalSnapshot({this.eps, this.bvps, this.roe});

  bool get isEmpty => eps == null && bvps == null && roe == null;
}

class FundamentalsSeries {
  final List<FinancialReport> reports;

  FundamentalsSeries(List<FinancialReport> reports)
      : reports = [...reports]
          ..sort((a, b) => a.published.compareTo(b.published));

  FundamentalSnapshot at(DateTime date) {
    double? eps, bvps, roe;
    for (final r in reports) {
      if (r.published.isAfter(date)) break;
      if (r.bvps > 0) bvps = r.bvps;
      if (r.season >= 4) {
        if (r.eps != 0) eps = r.eps;
        if (r.roe != null) roe = r.roe! / 100;
      }
    }
    return FundamentalSnapshot(eps: eps, bvps: bvps, roe: roe);
  }
}

/// Компанийн нэрээс ойролцоо салбар (MSE салбарын ангилал нийтэлдэггүй).
class SectorGuess {
  static const Map<String, List<String>> _keywords = {
    'Санхүү': ['банк', 'даатгал', 'ббсб', 'санхүү', 'кредит', 'лизинг',
      'сек', 'бирж', 'капитал', 'хөрөнгө оруулалт', 'инвест', 'финанс', 'lend'],
    'Уул уурхай, эрчим хүч': ['уул', 'ресурс', 'нүүрс', 'толгой', 'алт',
      'майнинг', 'эрдэнэ', 'түлш', 'газрын тос', 'петро', 'эрчим', 'цахилгаан',
      'дулаан', 'станц'],
    'Хүнс, хэрэглээ': ['хүнс', 'сүү', 'талх', 'чихэр', 'шувуу', 'мах',
      'гурил', 'ундаа', 'архи', 'апу', 'гоёл', 'говь', 'ноос', 'нэхий', 'арьс',
      'хувцас', 'гутал', 'монос', 'жимс'],
    'Барилга, үйлдвэр': ['барилга', 'бетон', 'цемент', 'материал', 'үйлдвэр',
      'машин', 'тоног', 'зам', 'гүүр'],
    'Худалдаа, үйлчилгээ': ['худалдаа', 'төв', 'зочид', 'буудал', 'тээвэр',
      'шуудан', 'логистик', 'харилцаа', 'холбоо', 'аялал', 'үйлчилгээ', 'ус'],
  };

  static String of(String name) {
    final n = name.toLowerCase();
    for (final e in _keywords.entries) {
      if (e.value.any(n.contains)) return e.key;
    }
    return 'Бусад';
  }
}

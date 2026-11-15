/// Хэрэглэгчийн эрсдэлийн профайл ба түүнд тохирох хуваарилалтын дүрмүүд.
class RiskProfile {
  /// UserPreferencesProvider-ийн утга ('Conservative' ... 'Aggressive').
  final String key;
  final String label;

  /// Бэлэн мөнгө / хадгаламжинд үлдээх зорилтот хувь.
  final double targetCash;

  /// Нэг хувьцаанд оногдуулах дээд хувь (нийт хөрөнгөөс).
  final double maxWeight;

  /// Багцад байх хувьцааны дээд тоо.
  final int maxPositions;

  /// Хэлбэлзлийг хэр их торгох вэ (их = хэлбэлзэл ихтэйгээс зайлсхийнэ).
  final double volPenalty;

  /// Жилийн хэлбэлзлийн хүлээн зөвшөөрөх дээд хэмжээ.
  final double maxAnnualVol;

  /// Хөрвөх чадварын доод хэмжээ (0..1). Бага бол зарахад хэцүү.
  final double minLiquidity;

  const RiskProfile({
    required this.key,
    required this.label,
    required this.targetCash,
    required this.maxWeight,
    required this.maxPositions,
    required this.volPenalty,
    required this.maxAnnualVol,
    required this.minLiquidity,
  });

  static const List<RiskProfile> all = [
    RiskProfile(
      key: 'Conservative',
      label: 'Консерватив',
      targetCash: 0.50,
      maxWeight: 0.10,
      maxPositions: 6,
      volPenalty: 2.0,
      maxAnnualVol: 0.35,
      minLiquidity: 0.8,
    ),
    RiskProfile(
      key: 'Moderately Conservative',
      label: 'Бага зэрэг консерватив',
      targetCash: 0.35,
      maxWeight: 0.12,
      maxPositions: 7,
      volPenalty: 1.5,
      maxAnnualVol: 0.45,
      minLiquidity: 0.7,
    ),
    RiskProfile(
      key: 'Moderate',
      label: 'Дунд',
      targetCash: 0.20,
      maxWeight: 0.15,
      maxPositions: 8,
      volPenalty: 1.0,
      maxAnnualVol: 0.60,
      minLiquidity: 0.6,
    ),
    RiskProfile(
      key: 'Moderately Aggressive',
      label: 'Бага зэрэг түрэмгий',
      targetCash: 0.10,
      maxWeight: 0.20,
      maxPositions: 8,
      volPenalty: 0.7,
      maxAnnualVol: 0.80,
      minLiquidity: 0.5,
    ),
    RiskProfile(
      key: 'Aggressive',
      label: 'Түрэмгий',
      targetCash: 0.05,
      maxWeight: 0.25,
      maxPositions: 10,
      volPenalty: 0.4,
      maxAnnualVol: 1.20,
      minLiquidity: 0.4,
    ),
  ];

  static RiskProfile fromKey(String key) =>
      all.firstWhere((p) => p.key == key, orElse: () => all[2]);
}

/// Эрсдэлийн профайлыг тодорхойлох асуумж.
class RiskQuestion {
  final String text;
  final List<String> options; // оноо = индекс (0..n-1)
  const RiskQuestion(this.text, this.options);
}

class RiskQuestionnaire {
  static const List<RiskQuestion> questions = [
    RiskQuestion('Та хөрөнгө оруулалтаа хэдэн жил барих вэ?', [
      '1 жилээс бага',
      '1–3 жил',
      '3–5 жил',
      '5-аас дээш жил',
    ]),
    RiskQuestion('Багцын үнэ 1 сарын дотор 20% унавал та юу хийх вэ?', [
      'Бүгдийг нь зарна',
      'Заримыг нь зарна',
      'Хүлээнэ',
      'Нэмж худалдаж авна',
    ]),
    RiskQuestion('Хөрөнгө оруулалтын гол зорилго тань юу вэ?', [
      'Мөнгөө хадгалах',
      'Инфляциас хамгаалах',
      'Тогтвортой өсөлт',
      'Хамгийн их өсөлт',
    ]),
    RiskQuestion('Энэ мөнгө таны нийт хуримтлалын хэдэн хувь вэ?', [
      '75%-аас их',
      '50–75%',
      '25–50%',
      '25%-аас бага',
    ]),
    RiskQuestion('Хувьцааны арилжааны туршлага тань?', [
      'Огт байхгүй',
      '1 жилээс бага',
      '1–3 жил',
      '3-аас дээш жил',
    ]),
    RiskQuestion('Аль хувилбарыг сонгох вэ?', [
      'Баталгаатай +5%',
      '+10% эсвэл 0%',
      '+20% эсвэл −10%',
      '+40% эсвэл −25%',
    ]),
  ];

  /// Хариултын индексүүдээс (0..3) эрсдэлийн профайлыг гаргана.
  static RiskProfile evaluate(List<int> answers) {
    final total = answers.fold<int>(0, (a, b) => a + b);
    final max = questions.length * 3;
    final ratio = total / max;
    final index = (ratio * RiskProfile.all.length)
        .floor()
        .clamp(0, RiskProfile.all.length - 1);
    return RiskProfile.all[index];
  }
}

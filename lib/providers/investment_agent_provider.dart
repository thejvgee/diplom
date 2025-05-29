import 'package:flutter/material.dart';

import '../models/holding.dart';
import '../models/transaction.dart';

class InvestmentAgentProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _hasError = false;
  String _error = '';
  Map<String, dynamic> _enhancedAnalysis = {};
  String _currentAdvice = '';
  List<Map<String, dynamic>> _portfolioSuggestions = [];
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get error => _error;
  bool get hasEnhancedAnalysis => _enhancedAnalysis.isNotEmpty;
  String get currentAdvice => _currentAdvice;
  List<Map<String, dynamic>> get portfolioSuggestions => _portfolioSuggestions;

  Future<void> getEnhancedPortfolioSuggestions({
    required List<Holding> holdings,
    required double cashBalance,
    required List<Transaction> transactions,
    required Map<String, dynamic> marketData,
    required String riskTolerance,
  }) async {
    try {
      _isLoading = true;
      _hasError = false;
      _error = '';
      notifyListeners();
      await Future.delayed(Duration(seconds: 3));
      _enhancedAnalysis = _generateMockAnalysis(
        holdings: holdings,
        cashBalance: cashBalance,
        transactions: transactions,
        marketData: marketData,
        riskTolerance: riskTolerance,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _hasError = true;
      _error = e.toString();
      notifyListeners();
    }
  }

  Map<String, dynamic> getPortfolioAnalysis() {
    if (!hasEnhancedAnalysis) return {};

    return {
      'overview': _enhancedAnalysis['analysis']['overview'],
      'strengths': _enhancedAnalysis['analysis']['strengths'],
      'weaknesses': _enhancedAnalysis['analysis']['weaknesses'],
    };
  }

  List<Map<String, dynamic>> getProcessedSuggestions() {
    if (!hasEnhancedAnalysis) return [];

    final List<dynamic> rawSuggestions = _enhancedAnalysis['suggestions'];
    return rawSuggestions
        .map((suggestion) => suggestion as Map<String, dynamic>)
        .toList();
  }

  void resetState() {
    _enhancedAnalysis = {};
    _isLoading = false;
    _hasError = false;
    _error = '';
    notifyListeners();
  }

  void clearError() {
    _hasError = false;
    _error = '';
    notifyListeners();
  }

  Future<void> getInvestmentAdvice({
    required String userQuestion,
    required Map<String, dynamic> portfolioData,
    required List<Map<String, dynamic>> marketTrends,
  }) async {
    try {
      _isLoading = true;
      _hasError = false;
      _error = '';
      notifyListeners();
      await Future.delayed(Duration(seconds: 2));
      _currentAdvice = _generateMockAdvice(userQuestion, portfolioData, marketTrends);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _hasError = true;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> getPortfolioSuggestions({
    required Map<String, dynamic> currentPortfolio,
    required Map<String, dynamic> userPreferences,
    required List<Map<String, dynamic>> marketData,
  }) async {
    try {
      _isLoading = true;
      _hasError = false;
      _error = '';
      notifyListeners();
      await Future.delayed(Duration(seconds: 2));
      _portfolioSuggestions = _generateMockSuggestions(
          currentPortfolio, userPreferences, marketData);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _hasError = true;
      _error = e.toString();
      notifyListeners();
    }
  }
  String _generateMockAdvice(String question, Map<String, dynamic> portfolio,
      List<Map<String, dynamic>> marketTrends) {
    question = question.toLowerCase();

    if (question.contains('tech') || question.contains('technology')) {
      return "Таны багц болон зах зээлийн өнөөгийн нөхцөл байдалд тулгуурлан технологийн салбарын хувьцаанууд ихээхэн боломжийг илэрхийлдэг. Гэсэн хэдий ч үнэлгээ өндөр байгаа тул нэг дор хөрөнгө оруулалт хийхээс илүүтэйгээр долларын өртгийн дундажийг авч үзэх хэрэгтэй.Тогтвортой өрсөлдөх давуу талтай компаниудад анхаарлаа хандуулаарай.";
    } else if (question.contains('diversif')) {
      return "Таны багцыг төрөлжүүлэх нь ашиг тусаа өгөх болно. Одоогийн байдлаар та хэдхэн салбарт өртөж байгаа бөгөөд энэ нь таны эрсдэлийг нэмэгдүүлдэг. Эрүүл мэнд, өргөн хэрэглээний бараа бүтээгдэхүүн, нийтийн аж ахуй гэх мэт өөр өөр салбарын хөрөнгийг нэмэх талаар бодож үзээрэй. ETF-ээр дамжуулан олон улсад өртөх нь таны багцыг тэнцвэржүүлэхэд тусална.";
    } else if (question.contains('эрсдэл')) {
      return "Таны багцын эрсдэлийн түвшин таны эзэмшилд тулгуурлан дунд зэрэг харагдаж байна. Эрсдэлийг бууруулахын тулд батлан ​​​​хамгаалах салбарууд болон бондуудад хуваарилалтаа нэмэгдүүлэх талаар бодож үзээрэй. Хэрэв та илүү эрсдэлд сэтгэл хангалуун байвал технологи, хэрэглэгчийн үзэмж зэрэг өсөлтөд чиглэсэн салбаруудад өртөх боломжийг нэмэгдүүлж болох ч албан тушаалын хэмжээг зөв тогтооно.";
    } else if (question.contains('хөрөнгө оруулалт') &&
        (question.contains('bear') ||
            question.contains('down') ||
            question.contains('recession'))) {
      return "Зах зээлийн уналтын үед хүчтэй баланс, тогтмол мөнгөн урсгал, өрсөлдөх давуу талтай чанартай компаниудад анхаарлаа хандуулаарай. Нийтийн аж ахуй, өргөн хэрэглээний бараа бүтээгдэхүүн, эрүүл мэнд зэрэг хамгаалалтын салбаруудыг авч үзье. Боломжуудыг ашиглахын тулд бэлэн мөнгө үлдээж, долларын өртгийн дундаж нь тогтворгүй үед үр дүнтэй стратеги байж болохыг санаарай.";
    } else {
      return "Таны одоогийн багцын хуваарилалт болон зах зээлийн нөхцөл байдалд үндэслэн өсөлт, үнэ цэнийн хөрөнгө оруулалтыг хослуулан тэнцвэртэй хандлагыг хадгалахыг зөвлөж байна. Зорилтот хөрөнгийн хуваарилалтаа хадгалахын тулд тогтмол тэнцвэржүүлэх талаар бодож, зах зээлийн өртгийг нэмэгдүүлэхийн өмнө яаралтай тусламжийн хангалттай хөрөнгөтэй байгаа эсэхийг шалгаарай. Тодорхой хөрөнгө оруулалтын зөвлөмж авахын тулд тодорхой салбар эсвэл хөрөнгө оруулалтын зорилгын талаар асууна уу.";
    }
  }

  List<Map<String, dynamic>> _generateMockSuggestions(
      Map<String, dynamic> portfolio,
      Map<String, dynamic> preferences,
      List<Map<String, dynamic>> marketData) {
    final String riskTolerance = preferences['riskTolerance'];
    final List<Map<String, dynamic>> suggestions = [];
    if (riskTolerance == 'Conservative') {
      suggestions.add({
        'asset': 'VYM',
        'action': 'Авах',
        'reason':
        'Өндөр ногдол ашиг бүхий ETF нь бага эрсдэлтэй хөрөнгө оруулагчдад тохиромжтой, тогтвортой орлоготой бага эргэлттэй орлого өгдөг.',
      });
      suggestions.add({
        'asset': 'GLMT',
        'action': 'Авах',
        'reason':
        'Бага эрсдэлтэй багцын хувьд таны санхүүгийн салбарын хувьцаа өндөр байна. Тогтворгүй байдлыг багасгахын тулд багасгах талаар бодож үзээрэй.',
      });
    } else if (riskTolerance == 'Moderate') {
      suggestions.add({
        'asset': 'VTI',
        'action': 'Авах',
        'reason':
        'Зах зээлийн ETF нь үндсэн багцын эзэмшилд хамгийн тохиромжтой хямд зардлаар өргөн хүрээг хамардаг.',
      });
      suggestions.add({
        'asset': 'APU',
        'action': 'Авах',
        'reason':
        'Хүчтэй балалнс, орлогын төрөл бүрийн урсгал нь өсөлтийг боломжийн тогтвортой байдлыг хангадаг.',
      });
    } else {
      // Өндөр эрсдэлтэй
      suggestions.add({
        'asset': 'AARD',
        'action': 'Авах',
        'reason':
        'Өндөр өсөлт нь таны өндөр эрсдэлтэй эрсдэлийн профайлтай нийцэж байгаа ч ихээхэн хэлбэлзэл бий болно.',
      });
      suggestions.add({
        'asset': 'GOV',
        'action': 'Авах',
        'reason':
        'Үйлдвэрлэлд төвлөрсөн GOVI нь өсөлтийн өндөр чадавхитай технологид өртөх боломжийг санал болгодог.',
      });
    }

    suggestions.add({
      'asset': 'Cash Reserves',
      'action': 'Maintain',
      'reason':
      'Онцгой байдлын үед 3-6 сарын зардлаа бэлнээр байлгаж, зах зээлийн боломжийг ашиглах.',
    });

    for (final trend in marketData) {
      if (trend['trend'] == 'Upward' && trend['confidence'] > 0.7) {
        suggestions.add({
          'asset': '${trend['sector']} ETF',
          'action': 'Buy',
          'reason':
          "${trend['sector']} салбарт хүчтэй өсөлтийн хандлага ажиглагдаж байна. Итгэлцлийн түвшин: ${(trend['confidence'] * 100).toStringAsFixed(0)}%."
        });
        break;
      }
    }

    return suggestions;
  }

  Map<String, dynamic> _generateMockAnalysis({
    required List<Holding> holdings,
    required double cashBalance,
    required List<Transaction> transactions,
    required Map<String, dynamic> marketData,
    required String riskTolerance,
  }) {
    double totalValue = holdings.fold<double>(
        0.0, (prev, h) => prev + (h.quantity * h.currentPrice)) +
        cashBalance;

    double techExposure = holdings
        .where((h) =>
    h.sector == 'Technology' ||
        h.symbol == 'AARD' ||
        h.symbol == 'APU' ||
        h.symbol == 'AIC')
        .fold<double>(
        0.0, (prev, h) => prev + (h.quantity * h.currentPrice)) /
        totalValue;

    double financeExposure = holdings
        .where((h) =>
    h.sector == 'Financials' ||
        h.symbol == 'GLMT' ||
        h.symbol == 'BDS' ||
        h.symbol == 'KHAN')
        .fold<double>(
        0.0, (prev, h) => prev + (h.quantity * h.currentPrice)) /
        totalValue;

    bool hasInternationalStocks = holdings
        .any((h) => h.symbol.endsWith('.L') || h.symbol.endsWith('.HK'));

    final List<String> strengths = [];
    final List<String> weaknesses = [];
    final List<Map<String, dynamic>> suggestions = [];

    if (holdings.length > 3) {
      strengths.add(
          'Таны хөрөнгө оруулалтын багц ${holdings.length} өөр хувьцаанаас бүрдэж байгаа нь давуу талтай яагаад гэвэл олон өөр хувьцаанаас багц бүрдүүлэх нь бага эрсдэлтэй.');
    }

    if (cashBalance > totalValue * 0.05) {
      strengths.add(
          'Таны багцад зориулсан боломжит хөрөнгө оруулалтын хувьд дансан дах үлдэгдэл багцийн (${(cashBalance / totalValue * 100).toStringAsFixed(1)}% байна.');
    }

    if (riskTolerance == 'Conservative' && cashBalance > totalValue * 0.1) {
      strengths.add(
          'Таны дансны үлдэгдэл бага эрсдэлтэй профайлтай сайн тохирч байна.');
    }

    if (riskTolerance == 'Aggressive' && techExposure > 0.3) {
      strengths.add(
          'Таны технологийн салбарт оруулсан өндөр хөрөнгө оруулалт нь өсөлтийн боломжийг олгох бөгөөд энэ нь таны өндөр эрсдэлтэй профайльтай сайн тохирч байна.');
    }

    if (holdings.length < 5) {
      weaknesses.add(
          'Зөвхөн ${holdings.length} holding-той байх нь таны хөрөнгө оруулалтын багцын хязгаарлаж байгаа бөгөөд эрсдлийг нэмэгдүүлж байна.');
    }

    if (techExposure > 0.4) {
      weaknesses.add(
          'Технологийн салбарын өндөр хувьцааны төвлөрөл (${(techExposure * 100).toStringAsFixed(1)}% тай  байх нь салбартай холбоотой эрсдлийг үүсгэж байна.');
    }

    if (!hasInternationalStocks) {
      weaknesses.add(
          'Олон улсын хөрөнгө оруулалтгүй байх нь санхүүгийн тогтвортой өргөжилтийг хязгаарладаг тул зөвхөн Монгол гэлтгүй олон улсын хувьцаа сонирхсон нь дээр.');
    }

    if (riskTolerance == 'Conservative' && techExposure > 0.25) {
      weaknesses.add(
          'Технологийн салбарт зориулагдсан ${(techExposure * 100).toStringAsFixed(1)}%-ийн хувьцаа нь таны бага эрсдэлтэй профайлтай тохирохгүй байна.');
    }

    if (riskTolerance == 'Aggressive' && cashBalance > totalValue * 0.15) {
      weaknesses.add(
          '${(cashBalance / totalValue * 100).toStringAsFixed(1)}%-ийн өндөр дансан дах мөнгө нь таны өндөр эрсдэлтэй профайлын хувьд өсөлтийн боломжийг хязгаарлах магадлалтай.');
    }
    String overview = 'Таны $riskTolerance -тэй профайлын дээр үндэслэн,';
    if (strengths.length > weaknesses.length) {
      overview +=
      'Таны багц сайн бүтэцтэй хэдий ч зарим нэг зүйлийг сайжруулах хэрэгтэй.';
    } else if (weaknesses.length > strengths.length) {
      overview +=
      'Таны багц зорилгоо биелүүлэхийн тулд зарим зүйлийг өөрчлөх шаардлагатай.';
    } else {
      overview +=
      'Таны багцад давуу тал байгаа хэдий ч анхаарал шаардлагатай сул хэсгүүд байна. ';
    }
    if (riskTolerance == 'Conservative') {
      if (techExposure > 0.25) {
        suggestions.add({
          'type': 'sell',
          'symbol': 'GLMT',
          'action': 'Санхүүгийн салбарын хувьцааг бууруулахыг санал болгоно.',
          'reasoning':
          'Таны технологийн салбарт зориулагдсан хувь нь бага эрсдэлтэй багцын хувьд өндөр байна. Өндөр хэлбэлзэлтэй технологийн хувьцааны хувийг бууруулах нь таны эрсдлийн түвшинтэй илүү сайн тохирч болно.'
        });
      }

      if (cashBalance < totalValue * 0.1) {
        suggestions.add({
          'type': 'allocate',
          'action': 'Орлогийг нэмэгдүүлэх хэрэгтэй.',
          'reasoning':
          'Таны бага эрсдэлтэй багцийн хувьд, хангалттай үлдэгдэл (багцийг 10-15%-ийг байлгах) нь тогтвортой байдлыг хангах ба зах зээлийн уналтад үнэт цаас худалдаж авах боломжийг олгоно.'
        });
      }

      suggestions.add({
        'type': 'buy',
        'symbol': 'APU',
        'action': 'Өндөр ногдол ашигтай хувьцаанд хөрөнгө оруулах хэрэгтэй.',
        'reasoning':
        'Өндөр ногдол ашигтай хувьцаанууд (жишээ нь: APU) нь тогтвортой орлого өгч, хэлбэлзлийг багасгадаг бөгөөд таны бага эрсдэлтэй багцтай сайн тохирч байна.'
      });
    } else if (riskTolerance == 'Moderate') {
      if (holdings.length < 5) {
        suggestions.add({
          'type': 'allocate',
          'action': 'Багцийн хүрээг нэмэгдүүлэх',
          'reasoning':
          '3-5 шинэ хувьцааг нэмж, ялгаатай салбаруудад хөрөнгө оруулах нь тухайн нэг хувьцааны эрсдлийг бууруулах боломжийг олгох ба дунд зэргийн өсөлтийн потенциалыг хадгалах болно.'
        });
      }

      if (!hasInternationalStocks) {
        suggestions.add({
          'type': 'buy',
          'symbol': 'BTC',
          'action': 'Олон улсын хөрөнгө оруулалт нэмэх',
          'reasoning':
          'Гадаад хувьцаа нь тогтвортой давуу талыг олгохоос гадна дэлхийн өсөлтийн боломжуудад нээлттэй болгоно. Энэ нь таны тэнцвэртэй эрсдэлтэй багцийг авахад тусална.'
        });
      }

      if (financeExposure < 0.1) {
        suggestions.add({
          'type': 'buy',
          'symbol': 'AARD',
          'action':
          'Санхүүгийн салбарт зориулсан хөрөнгө оруулалтыг нэмэхийг санал болгоно',
          'reasoning':
          'AARD гэх мэт санхүүгийн салбарын хувьцаанууд нь хүүний түвшин өсөх үед ашигтай байж, технологийн хувьцаанаас өргөжилт авах боломжийг олгодог.'
        });
      }
    } else if (riskTolerance == 'Aggressive') {
      if (cashBalance > totalValue * 0.15) {
        suggestions.add({
          'type': 'allocate',
          'action': 'Дансан дах үлдэгдэл ашиглах',
          'reasoning':
          'Таны дансан дах мөнгөний байршил нь өндөр эрсдэлтэй багцийн хувьд өндөр байна. Ашигтай боломжуудад капитал оруулах замаар боломжит орлогыг хамгийн их байлгахыг санал болгоно'
        });
      }

      suggestions.add({
        'type': 'buy',
        'symbol': 'APU',
        'action': 'Үйлдвэрлэлийн инноваци руу хөрөнгө оруулахыг санал болгоно',
        'reasoning':
        'Үйлдвэрлэлийн инновацид чиглэсэн (жишээ нь: APU) нь өндөр өсөлтийн боломжийг олгодог бөгөөд таны өндөр эрсдэлтэй багцтай сайн тохирч байна.'
      });

      if (!hasInternationalStocks) {
        suggestions.add({
          'type': 'buy',
          'symbol': 'GOV',
          'action': 'Хөгжиж буй зах зээл рүү хөрөнгө оруулах',
          'reasoning':
          'Хөгжиж буй зах зээлүүд (жишээ нь: Хятад) нь чухал өсөлтийн боломжуудыг олгодог бөгөөд таны өндөр эрсдэлтэй хөрөнгө оруулалтын хандлагатай тохирч байна'
        });
      }
    }
    suggestions.add({
      'type': 'allocate',
      'action': '5-10-40 дүрмийг дагах',
      'reasoning':
      'Илүү сайн багцийн төлөө таны багцийн хувьцаа бүрийг 5%-иас бага, салбар бүрийг 10%-иас бага, хөрөнгийн ангилал тус бүрийг 40%-иас бага хувьд байлгахыг санал болгоно.'
    });
    return {
      'analysis': {
        'overview': overview,
        'strengths': strengths,
        'weaknesses': weaknesses,
        'riskTolerance': riskTolerance,
        'portfolioValue': totalValue,
        'cashPercentage': cashBalance / totalValue,
        'sectorExposure': {
          'technology': techExposure,
          'financials': financeExposure,
        }
      },
      'suggestions': suggestions,
    };
  }
}

import 'package:flutter/material.dart';

import '../models/holding.dart';
import '../models/transaction.dart';

class InvestmentAgentProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _hasError = false;
  String _error = '';
  Map<String, dynamic> _enhancedAnalysis = {};

  // State for advice
  String _currentAdvice = '';
  List<Map<String, dynamic>> _portfolioSuggestions = [];

  // Getters
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

      // In a real app, this would make an API call to an AI service
      // For demo purposes, we'll simulate a response after a delay
      await Future.delayed(Duration(seconds: 3));

      // Generate mock AI response based on input data
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

  // Get investment advice based on user question
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

      // In a real app, this would make an API call to an AI service
      // For demo purposes, we'll simulate a response after a delay
      await Future.delayed(Duration(seconds: 2));

      // Generate mock advice based on the question
      _currentAdvice =
          _generateMockAdvice(userQuestion, portfolioData, marketTrends);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _hasError = true;
      _error = e.toString();
      notifyListeners();
    }
  }

  // Get portfolio suggestions
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

      // In a real app, this would make an API call to an AI service
      // For demo purposes, we'll simulate a response after a delay
      await Future.delayed(Duration(seconds: 2));

      // Generate mock suggestions
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

  // Generate mock advice based on user question
  String _generateMockAdvice(String question, Map<String, dynamic> portfolio,
      List<Map<String, dynamic>> marketTrends) {
    // Simple keyword matching for demo purposes
    question = question.toLowerCase();

    if (question.contains('tech') || question.contains('technology')) {
      return "Based on your portfolio and current market conditions, technology stocks represent a significant opportunity. However, valuations are high, so consider dollar-cost averaging into positions rather than investing all at once. Focus on companies with strong balance sheets and sustainable competitive advantages.";
    } else if (question.contains('diversif')) {
      return "Your portfolio could benefit from greater diversification. Currently, you have exposure to only a few sectors, which increases your risk. Consider adding assets from different sectors like healthcare, consumer staples, and utilities. International exposure through ETFs would also help balance your portfolio.";
    } else if (question.contains('risk')) {
      return "Your portfolio's risk level appears to be moderate based on your holdings. To reduce risk, consider increasing your allocation to defensive sectors and bonds. If you're comfortable with more risk, you might increase exposure to growth-oriented sectors like technology and consumer discretionary, but maintain proper position sizing.";
    } else if (question.contains('invest') &&
        (question.contains('bear') ||
            question.contains('down') ||
            question.contains('recession'))) {
      return "During market downturns, focus on quality companies with strong balance sheets, consistent cash flows, and competitive advantages. Consider defensive sectors like utilities, consumer staples, and healthcare. Keep some cash available to take advantage of opportunities, and remember that dollar-cost averaging can be an effective strategy during volatile periods.";
    } else {
      return "Based on your current portfolio allocation and market conditions, I recommend maintaining a balanced approach with a mix of growth and value investments. Consider regular rebalancing to maintain your target asset allocation, and ensure you have adequate emergency funds before increasing market exposure. For specific investment recommendations, please ask about particular sectors or investment goals.";
    }
  }

  // Generate mock portfolio suggestions
  List<Map<String, dynamic>> _generateMockSuggestions(
      Map<String, dynamic> portfolio,
      Map<String, dynamic> preferences,
      List<Map<String, dynamic>> marketData) {
    final String riskTolerance = preferences['riskTolerance'];
    final List<Map<String, dynamic>> suggestions = [];

    // Add suggestions based on risk tolerance
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

    // Add general suggestions
    suggestions.add({
      'asset': 'Cash Reserves',
      'action': 'Maintain',
      'reason':
          'Онцгой байдлын үед 3-6 сарын зардлаа бэлнээр байлгаж, зах зээлийн боломжийг ашиглах.',
    });

    // Add sector-specific suggestion based on market trends
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

  // Mock response generator for demo purposes
  Map<String, dynamic> _generateMockAnalysis({
    required List<Holding> holdings,
    required double cashBalance,
    required List<Transaction> transactions,
    required Map<String, dynamic> marketData,
    required String riskTolerance,
  }) {
    // Calculate some basic portfolio metrics
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
                h.symbol == 'GS')
            .fold<double>(
                0.0, (prev, h) => prev + (h.quantity * h.currentPrice)) /
        totalValue;

    bool hasInternationalStocks = holdings
        .any((h) => h.symbol.endsWith('.L') || h.symbol.endsWith('.HK'));

    // Generate appropriate analysis based on portfolio composition and risk tolerance
    final List<String> strengths = [];
    final List<String> weaknesses = [];
    final List<Map<String, dynamic>> suggestions = [];

    // Add common strengths
    if (holdings.length > 3) {
      strengths.add(
          'Таны хөрөнгө оруулалтын багц ${holdings.length} өөр хувьцаанаас бүрдэнэ.');
    }

    if (cashBalance > totalValue * 0.05) {
      strengths.add(
          'Таны багцад зориулсан боломжит хөрөнгө оруулалтын хувьд дансан дах үлдэгдэл багцийн (${(cashBalance / totalValue * 100).toStringAsFixed(1)}% байна');
    }

    // Add risk-specific strengths
    if (riskTolerance == 'Conservative' && cashBalance > totalValue * 0.1) {
      strengths.add(
          'Таны дансан дах их мөнгө бага эрсдэлтэй профайлтай сайн тохирч байна.');
    }

    if (riskTolerance == 'Aggressive' && techExposure > 0.3) {
      strengths.add(
          'Таны технологийн салбарт зориулагдсан өндөр хөрөнгө оруулалт нь өсөлтийн боломжийг олгох бөгөөд энэ нь таны өндөр эрсдэлтэй профайльтай сайн тохирч байна.');
    }

    // Add weaknesses
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
          'Олон улсын хөрөнгө оруулалтгүй байх нь санхүүгийн тогтвортой өргөжилтийг хязгаарладаг.');
    }

    if (riskTolerance == 'Conservative' && techExposure > 0.25) {
      weaknesses.add(
          'Технологийн салбарт зориулагдсан ${(techExposure * 100).toStringAsFixed(1)}%-ийн хувьцаа нь таны бага эрсдэлтэй профайлтай тохирохгүй байна.');
    }

    if (riskTolerance == 'Aggressive' && cashBalance > totalValue * 0.15) {
      weaknesses.add(
          '${(cashBalance / totalValue * 100).toStringAsFixed(1)}%-ийн өндөр дансан дах мөнгө нь таны өндөр эрсдэлтэй профайлын хувьд өсөлтийн боломжийг хязгаарлах магадлалтай.');
    }

    // Generate overview
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

    // Generate suggestions based on analysis and risk tolerance
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

    // Add a general diversification suggestion
    suggestions.add({
      'type': 'allocate',
      'action': '5-10-40 дүрмийг дагах',
      'reasoning':
          'Илүү сайн багцийн төлөө таны багцийн хувьцаа бүрийг 5%-иас бага, салбар бүрийг 10%-иас бага, хөрөнгийн ангилал тус бүрийг 40%-иас бага хувьд байлгахыг санал болгоно.'
    });

    // Build and return the complete analysis
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

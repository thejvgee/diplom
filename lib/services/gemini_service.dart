import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:math' as math;
import 'api_key_service.dart';
class GeminiService {
  static const String _basePrompt = '''
Та бол мэргэжлийн, туршлагатай хөрөнгө оруулагч, хиймэл оюун санхүүгийн зөвлөх.
• Хариулт: товч, ойлгомжтой, жишээ, тоо, хувь хэмжээтэй.
• Эрсдэл, зах зээлийн хэлбэлзлийг тусгах.
• Хэрэглэгчийн нөхцөлд тааруулсан зөвлөгөө.
• Томоохон шийдвэрийн өмнө мэргэжлийн зөвлөлдөхийг сануулах.
Таны хөрөнгө оруулалтын дүн дээр үндэслэн хамгийн сайн 10 хувьцаанууд ийм бүтэцтэй буцаана:
[SYMBOL]: [КОМПАНИЙН НЭР] - [МАШ ТОВЧ ШАЛТГААН]
''';
  late final String _fixedApiKey;
  late final String _backupApiKey;
  late GenerativeModel _model;
  final Connectivity _connectivity = Connectivity();
  int _errorCount = 0;
  static const int _maxErrorCount = 3;
  late String _currentApiKey;
  bool _usingBackupKey = false;
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  final Content _promptContent = Content.text(_basePrompt);
  GeminiService._internal();
  late final List<Content> _baseContents;

  Future<void> init() async {
    _fixedApiKey = await ApiKeyService.getGeminiApiKey();
    _backupApiKey = await ApiKeyService.getBackupGeminiApiKey();
    _currentApiKey = _fixedApiKey;
    _model = GenerativeModel(
      model: 'gemini-1.5-pro',
      apiKey: _currentApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.3,
        topP: 0.7,
        topK: 10,
        maxOutputTokens: 150,
      ),
    );
    _baseContents = [Content.text(_basePrompt)];
  }

  Future<bool> _checkConnectivity() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<bool> _switchToBackupKey() async {
    if (_usingBackupKey) return false;

    try {
      _currentApiKey = _backupApiKey;
      final newModel = GenerativeModel(
        model: 'gemini-1.5-pro',
        apiKey: _backupApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.5,
          topP: 0.8,
          topK: 20,
        ),
      );
      final testResponse = await newModel.generateContent([
        Content.text('Сайн уу!'),
      ]);

      if (testResponse.text != null && testResponse.text!.isNotEmpty) {
        _model = newModel;
        _usingBackupKey = true;
        print('Successfully switched to backup API key');
        return true;
      }

      return false;
    } catch (e) {
      print('Failed to switch to backup key: $e');
      return false;
    }
  }

  Future<String> startChat() async {
    try {
      final hasConnectivity = await _checkConnectivity();
      if (!hasConnectivity) {
        return "No internet connection. Please check your network settings and try again.";
      }
      final response = await _model.generateContent([
        ..._baseContents,
        Content.text('Сайн байна уу надад хөрөнгө оруулалтын зөвөлгөө хэрэгтэй байна.'),
      ]);
      if (response.text == null || response.text!.isEmpty) {
        return "Сайн уу! Би хөрөнгө оруулалтын хиймэл оюун зөвлөх байна. Би хөрөнгө оруулалтын стратеги, зах зээлийн шинжилгээ, мөн хувь хүний санхүүгийн шийдвэрүүдэд туслах боломжтой. Танд ямар мэдээлэл хэрэгтэй вэ?";
      }
      _errorCount = 0;
      return response.text!;
    } catch (e) {
      print('Error initializing chat: $e');
      _errorCount++;

      if (e.toString().contains('API key')) {
        bool switched = await _switchToBackupKey();
        if (switched) {
          return await startChat();
        }
      }
      if (e.toString().contains('No address associated with hostname')) {
        return "Unable to connect to the AI service. Please check your internet connection and try again.";
      } else if (e.toString().contains('Invalid API key')) {
        return "There was a problem with the AI service. Using backup service.";
      }
      return "Сайн уу! Би хөрөнгө оруулалтын зөвлөх AI байна. Өнөөдөр ямар хөрөнгө оруулалтын зөвөлгөө авах вэ?";
    }
  }

  Future<String> sendMessage(String message) async {
    final RegExp investmentRegex = RegExp(r'(have|got|with)\s+\d+\s*(dollars|usd|\$|money|rupees|rs|k)?.*\b(invest|investing|investment|stock|stocks)\b|\b(where|how)\s+to\s+invest\s+\d+', caseSensitive: false);
    if (investmentRegex.hasMatch(message.toLowerCase())) {
      return await getInvestmentRecommendations(message);
    }
    if (_errorCount >= _maxErrorCount) {
      return _getMockResponse(message);
    }
    try {
      final hasConnectivity = await _checkConnectivity();
      if (!hasConnectivity) {
        return "No internet connection. Please check your network settings and try again.";
      }
      final response = await _model.generateContent([
        ..._baseContents,
        Content.text(message),
      ]);
      if (response.text == null || response.text!.isEmpty) {
        return "Уучлаарай таны асуултанд хариулж чадсангүй. Асуултаа дахин бичээд үзээрэй.";
      }
      _errorCount = 0;
      return response.text!;
    } catch (e) {
      print('Error processing message: $e');
      _errorCount++;

      if (e.toString().contains('Invalid API key') && !_usingBackupKey) {
        bool switched = await _switchToBackupKey();
        if (switched) {
          return await sendMessage(message);
        }
      }
      if (_errorCount >= _maxErrorCount) {
        return _getMockResponse(message);
      }

      if (e.toString().contains('No address associated with hostname')) {
        return "Unable to connect to the AI service. Please check your internet connection and try again.";
      } else if (e.toString().contains('Invalid API key')) {
        return "I'm having trouble accessing my knowledge. Let me try a different approach.";
      }
      return "I apologize, but I encountered an error processing your request. Please try again.";
    }
  }

  Future<List<Map<String, dynamic>>> getStockRecommendations({required int count}) async {
    try {
      final hasConnectivity = await _checkConnectivity();
      if (!hasConnectivity) {
        return _getMockStockRecommendations();
      }

      final prompt = '''
Based on current market conditions, provide 5 stock recommendations in the following JSON format:
[
  {
    "symbol": "AARD",
    "name": "Ард санхүүгийн нэгдэл ХК.",
    "recommendation": "Buy",
    "confidence": 85,
    "reason": "Тогтвортой үйл ажилгаатай"
  },
  ...
]
Only respond with the JSON. No explanations or other text.
''';

      final response = await _model.generateContent([
        Content.text(prompt),
      ]);

      if (response.text == null || response.text!.isEmpty) {
        return _getMockStockRecommendations();
      }

      // Try to parse the JSON from the response
      try {
        // Extract JSON from response (removing any markdown code block syntax)
        String jsonText = response.text!
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final List<dynamic> parsed = jsonDecode(jsonText);
        return parsed.map((item) => Map<String, dynamic>.from(item)).toList();
      } catch (e) {
        print('Error parsing recommendation JSON: $e');
        return _getMockStockRecommendations();
      }
    } catch (e) {
      print('Error getting stock recommendations: $e');
      return _getMockStockRecommendations();
    }
    return _getMockStockRecommendations();
  }

  Future<List<Map<String, dynamic>>> getFinancialTips({int count = 5}) async {
    try {
      final hasConnectivity = await _checkConnectivity();
      if (!hasConnectivity) {
        return _getMockFinancialTips(count);
      }

      final prompt = '''
Provide 5 actionable financial tips in the following JSON format:
[
  {
    "title": "Emergency Fund First ",
    "description": "Build an emergency fund covering 3-6 months of expenses before investing",
    "category": "Savings"
  },
  ...
]
Only respond with the JSON. No explanations or other text.
''';

      final response = await _model.generateContent([
        Content.text(prompt),
      ]);

      if (response.text == null || response.text!.isEmpty) {
        return _getMockFinancialTips(count);
      }

      // Try to parse the JSON from the response
      try {
        // Extract JSON from response (removing any markdown code block syntax)
        String jsonText = response.text!
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final List<dynamic> parsed = jsonDecode(jsonText);
        return parsed.map((item) => Map<String, dynamic>.from(item)).toList();
      } catch (e) {
        print('Error parsing tips JSON: $e');
        return _getMockFinancialTips(count);
      }
    } catch (e) {
      print('Error getting financial tips: $e');
      return _getMockFinancialTips(count);
    }
    return _getMockFinancialTips(count);
  }

  Future<List<Map<String, dynamic>>> getMarketAlerts({int count = 3}) async {
    try {
      final hasConnectivity = await _checkConnectivity();
      if (!hasConnectivity) {
        return _getMockMarketAlerts(count);
      }

      final prompt = '''
Create 3 market alerts based on current market conditions in the following JSON format:
[
  {
    "title": "Tech Sector Correction",
    "description": "Technology stocks showing signs of a 5-7% correction in the coming weeks",
    "severity": "moderate",
    "impactedSectors": ["Technology", "Semiconductors"]
  },
  ...
]
Only respond with the JSON. No explanations or other text.
''';

      final response = await _model.generateContent([
        Content.text(prompt),
      ]);

      if (response.text == null || response.text!.isEmpty) {
        return _getMockMarketAlerts(count);
      }

      // Try to parse the JSON from the response
      try {
        // Extract JSON from response (removing any markdown code block syntax)
        String jsonText = response.text!
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final List<dynamic> parsed = jsonDecode(jsonText);
        return parsed.map((item) => Map<String, dynamic>.from(item)).toList();
      } catch (e) {
        print('Error parsing alerts JSON: $e');
        return _getMockMarketAlerts(count);
      }
    } catch (e) {
      print('Error getting market alerts: $e');
      return _getMockMarketAlerts(count);
    }
    return _getMockMarketAlerts(count);
  }

  Future<int> getPortfolioHealthScore(List<String> holdings) async {
    try {
      final hasConnectivity = await _checkConnectivity();
      if (!hasConnectivity) {
        return 75;
      }
      final prompt = 'Дараах хөрөнгө оруулалтын багцын health score-д 0-100 хооронд өгнө үү: ${holdings.join(', ')}. Үнэлгээ нь төрөлжилт, эрсдэлийн өртөлт, одоогийн зах зээлийн нөхцөл зэрэг хүчин зүйлсийг харгалзан үзнэ. Зөвхөн тоон үнэлгээг буцаана уу.';
      final response = await _model.generateContent([
        ..._baseContents,
        Content.text(prompt),
      ]);
      if (response.text == null || response.text!.isEmpty) {
        return 50;
      }
      final score = int.tryParse(response.text!.trim()) ?? 50;
      _errorCount = 0;
      return score;
    } catch (e) {
      print('Error getting portfolio health score: $e');
      _errorCount++;
      if (e.toString().contains('Invalid API key') && !_usingBackupKey) {
        bool switched = await _switchToBackupKey();
        if (switched) {
          return await getPortfolioHealthScore(holdings);
        }
      }
      return 75;
    }
  }

  String _getMockResponse(String message) {
    message = message.toLowerCase();

    final RegExp investmentRegex = RegExp(r'\b(stock|invest|etf|fund)s?\b', caseSensitive: false);
    if (investmentRegex.hasMatch(message)) {
      return _getMockInvestmentRecommendations();
    } else if (message.contains('crypto') || message.contains('bitcoin') || message.contains('blockchain')) {
      return "Cryptocurrency remains a highly volatile asset class with significant risk and potential reward. Based on historical volatility metrics, Bitcoin has shown standard deviations of returns 3-4 times higher than traditional equity markets.\n\nIf you're considering crypto investments, I recommend the following approach:\n\n• Limit total crypto exposure to 5-10% of your overall investment portfolio\n• Allocate 60-70% of your crypto portfolio to established cryptocurrencies (Bitcoin, Ethereum)\n• Diversify the remaining 30-40% across 3-5 mid-cap cryptocurrencies\n• Implement dollar-cost averaging by investing fixed amounts at regular intervals\n• Consider a 2-year minimum investment horizon due to market cycles\n\nRisk management strategies:\n• Set stop-loss orders at 15-20% below purchase price\n• Take partial profits when positions gain 50-100%\n• Maintain detailed records for tax reporting (crypto transactions face different tax treatment)\n\nActionable steps:\n1. Research reputable exchanges with strong security measures\n2. Start with a small position and increase gradually as you gain experience\n3. Create a separate emergency fund before investing in crypto\n\nDisclaimer: This is AI-generated advice. Cryptocurrency investments carry significant risk of loss. Consult with a financial professional who specializes in digital assets before investing.";
    } else if (message.contains('budget') || message.contains('save') || message.contains('spending')) {
      return "A structured budgeting approach is the foundation of financial stability. Based on financial planning best practices, I recommend the 50/30/20 framework as a starting point:\n\n• 50% for necessities (housing, utilities, groceries, transportation, insurance)\n• 30% for discretionary spending (dining out, entertainment, shopping)\n• 20% for financial goals (emergency fund, debt repayment, retirement)\n\nTo implement this effectively:\n\n1. Track all expenses for 30 days using a spreadsheet or budgeting app\n2. Categorize each expense and calculate category percentages\n3. Identify spending categories that exceed recommended percentages\n4. Target 2-3 specific categories for 10-15% reduction\n\nFor emergency savings, aim for 3-6 months of essential expenses (approximately \$10,000-\$25,000 for most households) in a high-yield savings account (currently offering 3-4% APY).\n\nDebt repayment strategy:\n• Focus on high-interest debt first (typically credit cards at 15-25% APR)\n• Consider consolidating high-interest debt to lower rates when possible\n• Maintain minimum payments on all debts while accelerating payoff of highest-rate debt\n\nActionable steps:\n1. Set up automatic transfers to savings on payday (pay yourself first)\n2. Review and cancel unused subscriptions (average household spends \$273/month)\n3. Implement a 24-hour rule for non-essential purchases over \$100\n\nDisclaimer: This is AI-generated advice based on general financial principles. Your specific situation may require adjustments to these recommendations.";
    } else if (message.contains('retire') || message.contains('401k') || message.contains('ira')) {
      return "Retirement planning requires balancing current needs with long-term security. Based on financial planning models, most individuals need to replace 70-80% of their pre-retirement income to maintain their lifestyle.\n\nHere's a strategic approach to retirement savings by age:\n\n• 20s: Aim to save 10-15% of gross income, focusing on tax-advantaged accounts\n• 30s: Increase to 15-20% of income with a 70/30 stock/bond allocation\n• 40s: Target 20-25% of income with a 60/40 stock/bond allocation\n• 50s: Maximize catch-up contributions and shift to 50/50 allocation\n\nAccount prioritization strategy:\n1. Contribute enough to employer 401(k) to get full match (immediate 50-100% return)\n2. Max out HSA if eligible (triple tax advantage)\n3. Max out Roth IRA if income eligible (\$6,500/year, \$7,500 if over 50)\n4. Return to 401(k) up to annual limit (\$22,500, plus \$7,500 catch-up if over 50)\n5. Consider backdoor Roth or taxable accounts for additional savings\n\nThe power of compounding: \$10,000 invested at age 25 with 7% average returns grows to approximately \$150,000 by age 65, while the same amount invested at 45 grows to only \$38,700.\n\nActionable steps:\n1. Increase your retirement contribution rate by 1% every six months\n2. Consolidate old employer retirement accounts to simplify management\n3. Schedule an annual retirement planning review to adjust contributions\n\nDisclaimer: This is AI-generated advice based on general retirement planning principles. Consult with a qualified financial advisor to create a personalized retirement strategy.";
    } else {
      return "Таны асуултыг ойлголоо. Таны хувийн санхүүгийн байдлын талаар тодорхой мэдээлэл надад байхгүй ч би ихэнх санхүүгийн шийдвэрт хамаарах эдгээр үндсэн зарчмуудыг санал болгож чадна:\n\n• Эрсдэл ба өгөөж нь үндсэндээ холбоотой байдаг - өндөр боломжит өгөөж нь ихэвчлэн өндөр хэлбэлзлийг хүлээн зөвшөөрдөг.\n• Хөрөнгийн ангиллаар хуваах нь багцын эрсдэлийг зах зээлийн хүлээгдэж буй өгөөжийг 25-40%-иар бууруулах боломжтой. Инфляцийг цаг хугацааны хувьд давж гарна - тогтмол хөрөнгө оруулалт нь  эрсдэл өндөртэй хөрөнгө оруулалтаас илүү.\n• Татварын шимтгэл нь урт хугацааны хөрөнгө оруулалтанд  ихээхэн нөлөөлнө - өөр өөр төрлийн хувьцааны байрлалын оновчлолыг авч үзэх\n\nСанхүүгийн тэргүүлэх чиглэлүүдийг санал болгож буй дарааллаар авч үзэх:\n1. 3-6 сарын хамгийн их зээлийн өрийг нөхөх боломжтой картууд)\n3. Ажил олгогчийн тэтгэврийн шимтгэлийг зохих даатгалд хамруулах замаар гамшгийн эрсдэлээс хамгаалах\n5. Татварын давуу талтай дансуудад урт хугацааны зорилгын төлөө хөрөнгө оруулалт хийх\n\nҮйл ажиллагаа явуулах боломжтой алхамууд:\n1. Орлого, зарлага, хөрөнгө, өр төлбөртөө иж бүрэн дүн шинжилгээ хийх\n2. Тодорхой, хэмжиж болохуйц санхүүгийн зорилтуудыг зорилтот огноогоор тодорхойл.\n3. Хадгаламж, хөрөнгө оруулалтын автоматжуулсан хувь нэмрийг хэрэгжүүлнэ үү\n\nТатгалзах: Энэ бол санхүүгийн ерөнхий зарчимд суурилсан хиймэл оюун ухаанаас бий болгосон зөвлөгөө юм. Таны нөхцөл байдалд тохирсон хувийн удирдамж авахын тулд мэргэшсэн санхүүгийн мэргэжилтэнтэй зөвлөлдөнө үү.";    }
  }
  List<Map<String, dynamic>> getRandomRecommendations({int count = 5}) {
    return _getMockStockRecommendations(count: count);
  }
  final _allRecommendations = <Map<String, dynamic>>[
    {
      "symbol": "AARD",
      "name": "Ард санхүүгийн нэгдэл ХК.",
      "recommendation": "Buy",
      "confidence": 85,
      "reason": "Даатгал, хөрөнгө оруулалт зэрэг олон салбарт хөрөнгө оруулалттай, өсөлтийн өндөр боломжтой, дижитал шилжилт хийж буй хүчирхэг санхүүгийн нэгдэл."
    },
    {
      "symbol": "ADB",
      "name": "Ард кредит ББСБ ХК.",
      "recommendation": "Strong Buy",
      "confidence": 90,
      "reason": "Технологид суурилсан зээл, хуримтлал, кредит картын үйлчилгээ үзүүлдэг, өсөлттэй, хүртээмжтэй санхүүгийн үйлчилгээ бүхий Ард Санхүүгийн Нэгдлийн охин компани."
    },
    {
      "symbol": "AIC",
      "name": "Ард Даатгал ХК.",
      "recommendation": "Buy",
      "confidence": 82,
      "reason": "Даатгалын салбарт тэргүүлэгчдийн нэг, дижитал даатгалын шийдлүүдийг нэвтрүүлж буй, тогтвортой орлого, өсөлтийн боломжтой, Ард Санхүүгийн Нэгдлийн бүрэлдэхүүнд багтдаг."
    },
    {
      "symbol": "APU",
      "name": "АПУ ХК.",
      "recommendation": "Buy",
      "confidence": 84,
      "reason": "Монголын хамгийн том ундаа, архины үйлдвэрлэгч, тогтвортой ногдол ашиг олгодог, дотоодын болон экспортын зах зээлд өрсөлдөх чадвартай, олон жилийн туршлагатай компани."
    },
    {
      "symbol": "BDS",
      "name": "Би ди сек ХК",
      "recommendation": "Hold",
      "confidence": 74,
      "reason": "Үнэт цаасны арилжаа, хөрөнгө оруулалтын зөвлөх үйлчилгээ үзүүлдэг, хөрөнгийн зах зээлд идэвхтэй оролцдог, өсөлтийн боломжтой, туршлагатай багтай брокер дилер компани."
    },
    {
      "symbol": "BODI",
      "name": "Бодь Даатгал ХК",
      "recommendation": "Sell",
      "confidence": 65,
      "reason": "Даатгалын үйлчилгээ үзүүлдэг, санхүүгийн зах зээлд идэвхтэй оролцдог, өсөлтийн боломжтой, олон жилийн туршлагатай, найдвартай багтай даатгалын компани."
    },
    {
      "symbol": "GAZR",
      "name": "Газар Шим Үйлдвэр ХК",
      "recommendation": "Hold",
      "confidence": 74,
      "reason": "Даршилсан жимс, хүнсний ногооны үйлдвэрлэл эрхэлдэг, хүнсний үйлдвэрлэлийн салбарт идэвхтэй оролцдог, өсөлтийн боломжтой, туршлагатай багтай, органик бүтээгдэхүүн үйлдвэрлэдэг хүнсний компани."
    },
    {
      "symbol": "GLMT",
      "name": "Голомт Банк ХК",
      "recommendation": "Buy",
      "confidence": 84,
      "reason": "Банк, санхүүгийн цогц үйлчилгээ үзүүлдэг, Монголын санхүүгийн зах зээлд идэвхтэй оролцдог, өсөлтийн өндөр боломжтой, туршлагатай багтай, системийн чухал ач холбогдол бүхий тэргүүлэгч арилжааны банк."
    },
    {
      "symbol": "GOV",
      "name": "Говь ХК",
      "recommendation": "Strong buy",
      "confidence": 91,
      "reason": "100% Монгол ноолуураар тансаг зэрэглэлийн бүтээгдэхүүн үйлдвэрлэдэг, дэлхийн зах зээлд идэвхтэй оролцдог, өсөлтийн өндөр боломжтой, 40 гаруй жилийн туршлагатай, олон улсын чанарын стандартад нийцсэн үндэсний үйлдвэрлэгч компани. "
    },
    {
      "symbol": "INV",
      "name": "Инвескор ББСБ ХК",
      "recommendation": "Sell",
      "confidence": 62,
      "reason": "Зээлийн үйлчилгээ, факторинг, итгэлцлийн үйлчилгээ зэрэг банк бус санхүүгийн үйл ажиллагаа эрхэлдэг, Монголын санхүүгийн зах зээлд идэвхтэй оролцдог, өсөлтийн өндөр боломжтой, дэвшилтэт технологи, туршлагатай багтай банк бус санхүүгийн байгууллага. "
    },
    {
      "symbol": "KHAN",
      "name": "Хаан банк ХК",
      "recommendation": "Strong buy",
      "confidence": 94,
      "reason": "Банк, санхүүгийн цогц үйлчилгээ үзүүлдэг, Монголын санхүүгийн зах зээлд идэвхтэй оролцдог, өсөлтийн өндөр боломжтой, туршлагатай багтай, системийн чухал ач холбогдол бүхий тэргүүлэгч арилжааны банк."
    },
    {
      "symbol": "LEND",
      "name": "ЛэндМН ББСБ ХК",
      "recommendation": "Buy",
      "confidence": 80,
      "reason": "Хиймэл оюун ухаанд суурилсан финтек үйлчилгээ үзүүлдэг, Монголын санхүүгийн зах зээлд идэвхтэй оролцдог, өсөлтийн өндөр боломжтой, технологид суурилсан инноваци бүхий, туршлагатай багтай банк бус санхүүгийн байгууллага."
    },
  ];
  List<Map<String, dynamic>> _getMockStockRecommendations({int count = 5}) {
    final rnd = math.Random();
    final buffer = List<Map<String, dynamic>>.from(_allRecommendations);
    buffer.shuffle(rnd);
    return buffer.take(count.clamp(1, buffer.length)).toList();
  }

  final List<Map<String, dynamic>> _allFinancialTips = [
    {
      "title": "Нөөц хуримтлал",
      "description": "Их хэмжээний хөрөнгө оруулалт хийхээсээ өмнө 3-6 сарын зардлыг нөхөх яаралтай хадгаламж нээ.",
      "category": "Savings"
    },
    {
      "title": "Татварын давуу эрхтэй дансууд",
      "description": "Татварын хөнгөлөлттэй данс руу ихээр хөрөнгө оруулж, дараа нь татвар ногдох данс ашигла.",
      "category": "Investing"
    },
    {
      "title": "Өрийн нэмэгдэл",
      "description": "Хамгийн бага өрөөс эхэлж төл.",
      "category": "Debt Management"
    },
    {
      "title": "Дундаж зардлаар хөрөнгө оруулах",
      "description": "Зах зээлийн нөхцөлөөс үл хамааран тогтмол хэмжээний хөрөнгө оруулалт хийж, цаг хугацааны эрсдэлийг бууруул.",
      "category": "Investing"
    },
    {
      "title": "Зардалаа хянах",
      "description": "30 хоногийн турш бүх зардлаа хөтөлж, зарлагын хэв маяг, хэмнэх аргаа ол.",
      "category": "Budgeting"
    },
    {
      "title": "Тэтгэврийн хуримтлал төлөвлөлт",
      "description": "Өнөөдрөөс эхлэн сар бүр тэтгэврийн хуримтлал руу бага ч болов хөрөнгө шилжүүлж, урт хугацааны санхүүгийн аюулгүй байдлаа баталгаажуул.",
      "category": "Retirement Planning"
    },
    {
      "title": "Даатгалын хамгаалалт",
      "description": "Амьдрал, эрүүл мэнд, үл хөдлөлийн даатгалд хөрөнгө оруулж, эрсдэлийн үед санхүүгийн ачааллыг бууруул.",
      "category": "Insurance"
    },
    {
      "title": "Татварын төлөвлөлт",
      "description": "Жилийн орлого, зарлагаа нарийвчлан тооцож, боломжит татварын хөнгөлөлт, буцаан олголтыг урьдчилан төлөвлө.",
      "category": "Tax Planning"
    },
    {
      "title": "Салбарын төрөлжилт",
      "description": "Хөрөнгө оруулалтаа янз бүрийн салбар, бүс нутагт тарааж, зах зээлийн хэлбэлзлээс хамгаал.",
      "category": "Diversification"
    },
    {
      "title": "Яаралтай тусламжийн сан",
      "description": "Гэнэтийн эмнэлгийн зардал, механик эвдрэл зэрэгт зориулагдсан тусгай хуримтлал бий болго.",
      "category": "Emergency Planning"
    },
    {
      "title": "Боловсролын хуримтлал",
      "description": "Хүүхдийн ирээдүйд зориулан сургууль, коллежийн зардалдаа зориулсан тусгай данс нээ.",
      "category": "Education Savings"
    },
    {
      "title": "Кэш урсгалын удирдлага",
      "description": "Орлого, зарлагыг тогтмол шалгаж, богино болон дундаж хугацааны асуудлыг хурдан шийдвэрлэхэд шаардлагатай нөөцийг бэлтгэ.",
      "category": "Cash Flow Management"
    },
    {
      "title": "Тодорхой зорилго тавих",
      "description": "Өөрийн санхүүгийн зорилго (байр худалдаж авах, аялал, тэтгэврийн хуримтлал) тодорхойлох, хугацаа, хэмжээг нарийн тогтоох.",
      "category": "Goal Setting"
    },
    {
      "title": "Орлогын хэдэн эх үүсвэр",
      "description": "Үндсэн орлогоос гадна түр орлого, хөрөнгө оруулалтын ашиг зэргээр орлогын хэд хэдэн эх үүсвэр бий болго.",
      "category": "Asset Allocation"
    },
    {
      "title": "Эрсдэлийн менежмент",
      "description": "Хөрөнгө оруулалт бүрийн эрсдэлийг үнэлж, шаардлагатай тохиолдолд зөрчилдөхгүй санхүүгийн стратеги боловсруул.",
      "category": "Risk Management"
    }
  ];
  List<Map<String, dynamic>> _getMockFinancialTips(int count) {
    final rnd = math.Random();
    final buffer = List<Map<String, dynamic>>.from(_allFinancialTips);
    buffer.shuffle(rnd);
    return buffer.take(count.clamp(1, buffer.length)).toList();
  }
  final List<Map<String, dynamic>> _allMarketAlerts = [
    {
      "title": "Технологийн салбарын хэлбэлзэл – NVIDIA Corp.",
      "description": "Хүүгийн түвшний тодорхойгүй байдал нь NVIDIA Corp. (NVDA)–ын хувьцааны үнийн хэлбэлзлийг нэмэгдүүлж байна",
      "severity": "moderate",
      "impactedSectors": ["Semiconductor Manufacturer"]
    },
    {
      "title": "Эрчим хүчний салбарын боломж – Exxon Mobil Corp.",
      "description": "Одоогийн түүхий эдийн үнэ болон эрэлтийн таамаглалтай харьцуулахад Exxon Mobil Corp. (XOM)–ын хувьцааны үнэлгээ харьцангуй бага байна",
      "severity": "low",
      "impactedSectors": ["Oil & Gas Major"]
    },
    {
      "title": "Инфляцын өсөлт – Procter & Gamble Co.",
      "description": "Сүүлийн саруудад инфляцын хурд нэмэгдэж, Procter & Gamble Co. (PG)–ын ногдол ашигт дарамт үзүүлэх эрсдэлтэй байна",
      "severity": "high",
      "impactedSectors": ["FMCG Manufacturer"]
    },
    {
      "title": "Валютын ханшийн хэлбэлзэл – Erdenes Tavan Tolgoi JSC",
      "description": "Ам доллар болон төгрөгийн солилцооны ханшийн хэлбэлзэл нь Erdenes Tavan Tolgoi JSC (ETT)–ын орлогод шууд нөлөөлж байна",
      "severity": "moderate",
      "impactedSectors": ["Mining & Exploration"]
    },
    {
      "title": "Барилга зах зээлийн хөлдөөлт – Brookfield Asset Management",
      "description": "Орон сууцны эрэлт буурсных Brookfield Asset Management (BAM)–ын барилгын портфелийн ашигт ажиллагаанд дарамт үүсэж байна",
      "severity": "low",
      "impactedSectors": ["Real Estate Investment Trust"]
    },
    {
      "title": "Материалын үнийн өсөлт – BHP Group Ltd.",
      "description": "Зэс болон төмрийн хүдрийн үнэ огцом өсөж, BHP Group Ltd. (BHP)–ын үйлдвэрлэлийн зардал нэмэгдэж байна",
      "severity": "high",
      "impactedSectors": ["Mining Company"]
    },
    {
      "title": "Харилцаа холбооны салбарын сэргэлт – Verizon Communications Inc.",
      "description": "Цар тахлын дараах дижитал шилжилт нь Verizon Communications Inc. (VZ)–д хөрөнгө оруулалтын сонирхол нэмэгдүүлж байна",
      "severity": "moderate",
      "impactedSectors": ["Telecommunications Provider"]
    },
    {
      "title": "Санхүүгийн салбарын зохицуулалт – JPMorgan Chase & Co.",
      "description": "Шинэ хууль, дүрэм журмууд JPMorgan Chase & Co. (JPM)–ын үйл ажиллагаанд нөлөөлж болзошгүй",
      "severity": "moderate",
      "impactedSectors": ["Global Bank"]
    },
    {
      "title": "Хэрэглээний салбар дахь улирлын уналт – Amazon.com Inc.",
      "description": "Худалдан авалтын улирлын бууралт нь Amazon.com Inc. (AMZN)–ын жижиглэн худалдааны борлуулалтад түр хугацаанд сөргөөр нөлөөлж байна",
      "severity": "low",
      "impactedSectors": ["E-commerce Retailer"]
    }
  ];
  List<Map<String, dynamic>> _getMockMarketAlerts(int count) {
    final rnd = math.Random();
    final buffer = List<Map<String, dynamic>>.from(_allMarketAlerts);
    buffer.shuffle(rnd);
    return buffer.take(count.clamp(1, buffer.length)).toList();
  }

  // Get specific investment recommendations based on amount
  Future<String> getInvestmentRecommendations(String message) async {
    try {
      final hasConnectivity = await _checkConnectivity();
      if (!hasConnectivity) {
        return _getMockInvestmentRecommendations();
      }

      // Extract the investment amount from the message
      final RegExp amountRegex = RegExp(r'\b(\d{1,3}(?:,\d{3})*|\d+)\s*(?:dollars|usd|\$|money|rupees|rs)?\b', caseSensitive: false);
      final match = amountRegex.firstMatch(message);
      String amount = "";

      if (match != null) {
        amount = match.group(1) ?? "";
        // Remove commas from the amount
        amount = amount.replaceAll(',', '');
      }

      final prompt = '''
${_basePrompt}

The user has $amount to invest. Provide a VERY CONCISE list of 5 specific investment recommendations (stocks, ETFs, etc.) that would be suitable for this amount. Format your response as follows:

Based on your investment amount of $amount, here are the best options:

1. [SYMBOL]: [COMPANY NAME] - [VERY BRIEF REASON]
2. [SYMBOL]: [COMPANY NAME] - [VERY BRIEF REASON]
3. [SYMBOL]: [COMPANY NAME] - [VERY BRIEF REASON]
4. [SYMBOL]: [COMPANY NAME] - [VERY BRIEF REASON]
5. [SYMBOL]: [COMPANY NAME] - [VERY BRIEF REASON]

Keep each reason to 10 words or less. Be extremely concise.
''';

      final response = await _model.generateContent([
        Content.text(prompt),
      ]);

      if (response.text == null || response.text!.isEmpty) {
        return _getMockInvestmentRecommendations();
      }

      // Reset error count on successful request
      _errorCount = 0;
      return response.text!;
    } catch (e) {
      print('Error getting investment recommendations: $e');
      return _getMockInvestmentRecommendations();
    }
  }

  // Provide mock investment recommendations when API fails
  String _getMockInvestmentRecommendations() {
    return "Таны хөрөнгө оруулалтын хэмжээнд үндэслэн дараах хувьцаа, ETF-үүдийг санал болгож байна:\n\n" +
        "1. VTI – Vanguard Total Stock Market ETF - АНУ-ын нийт хөрөнгийн зах зээлийг хамарсан, бага шимтгэлтэй, өргөн хүрээний хөрөнгө оруулалт.\n" +
        "2. APU: АПУ ХК. - Хүчирхэг бүтээгдэхүүний экосистем, үйлчилгээний салбарын өсөлттэй.\n" +
        "3. AARD: Ард Санхүүгийн Нэгдэл ХК - даатгал, хөрөнгө оруулалт зэрэг олон салбарт хөрөнгө оруулалттай, өсөлтийн өндөр боломжтой хүчирхэг санхүүгийн нэгдэл.\n" +
        "4. AIC: Ард Даатгал ХК. - Даатгалын салбарт тэргүүлэгчдийн нэг, дижитал даатгалын шийдлүүдийг нэвтрүүлж буй, тогтвортой орлого, өсөлтийн боломжтой, Ард Санхүүгийн Нэгдлийн бүрэлдэхүүнд багтдаг.\n" +
        "5. BDS: Би Ди Сек ХК - Үнэт цаасны арилжаа, хөрөнгө оруулалтын зөвлөх үйлчилгээ үзүүлдэг, хөрөнгийн зах зээлд идэвхтэй оролцдог, өсөлтийн боломжтой, туршлагатай багтай брокер дилер компани.\n\n" +
        "Хөрөнгө оруулалтын эрсдэлийг бууруулахын тулд тогтмол дүнгээр хөрөнгө оруулах (Dollar-Cost Averaging) аргыг ашиглаарай.";
  }

  void dispose() {
    // Nothing to dispose
  }
}

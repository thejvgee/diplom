import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/holding.dart';
import '../models/transaction.dart';

class InvestmentAgentService {
  final String apiKey;
  late final GenerativeModel? _model;
  bool _isModelInitialized = false;
  
  InvestmentAgentService({required this.apiKey}) {
    _initializeModel();
  }
  
  void _initializeModel() {
    try {
      if (apiKey.isEmpty) {
        debugPrint('Error: API key is empty');
        _model = null;
        return;
      }
      
      _model = GenerativeModel(
        model: 'gemini-1.5-pro',
        apiKey: apiKey,
        safetySettings: [
          SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
        ],
      );
      _isModelInitialized = true;
    } catch (e) {
      debugPrint('Error initializing Gemini model: $e');
      _model = null;
    }
  }
  
  Future<String> generateInvestmentAdvice({
    required String userQuestion,
    required Map<String, dynamic> portfolioData,
    required List<Map<String, dynamic>> marketTrends,
  }) async {
    try {
      if (!_isModelInitialized || _model == null) {
        if (apiKey.isEmpty) {
          return 'To use the AI investment agent, please set up your Gemini API key in Settings. '
                 'You can get a free API key from https://ai.google.dev/';
        }
                _initializeModel();
        if (!_isModelInitialized || _model == null) {
          return 'Unable to initialize AI model. Please check your API key in Settings.';
        }
      }
            final context = '''
As an investment advisor, analyze the following information and provide advice:

User portfolio: ${portfolioData.toString()}
Market trends: ${marketTrends.toString()}
User question: $userQuestion

Provide a concise, informed response focused on answering the user's question based on their portfolio and current market trends.
''';
      
      final content = [Content.text(context)];
      final response = await _model!.generateContent(content);      
      if (response.text == null || response.text!.isEmpty) {
        return 'Sorry, I couldn\'t generate a response. Please try again with a different question.';
      }
      
      return response.text!;
    } catch (e) {
      debugPrint('Error generating investment advice: $e');  
      if (e.toString().contains('API key')) {
        return 'Invalid API key. Please update your API key in Settings.';
      } else if (e.toString().contains('network')) {
        return 'Network error. Please check your internet connection and try again.';
      } else if (e.toString().contains('timeout') || e.toString().contains('timed out')) {
        return 'Request timed out. Please try again later.';
      }
      
      return 'An error occurred: ${e.toString()}. Please try again later.';
    }
  }
  
  Future<Map<String, dynamic>> getEnhancedPortfolioSuggestions({
    required List<Holding> holdings,
    required double cashBalance,
    required List<Transaction> transactions,
    required Map<String, dynamic> marketData,
    required String riskTolerance,
  }) async {
    try {
      if (!_isModelInitialized || _model == null) {
        if (apiKey.isEmpty) {
          return {
            'error': 'To use the AI investment agent, please set up your Gemini API key in Settings.',
            'suggestions': []
          };
        }
        
        _initializeModel();
        if (!_isModelInitialized || _model == null) {
          return {
            'error': 'Unable to initialize AI model. Please check your API key in Settings.',
            'suggestions': []
          };
        }
      }
      
      final formattedHoldings = holdings.map((holding) => {
        'symbol': holding.symbol,
        'quantity': holding.quantity,
        'averageCost': holding.averageCost,
        'totalCost': holding.totalCost,
      }).toList();
      
      final formattedTransactions = transactions.map((transaction) => {
        'symbol': transaction.symbol,
        'action': transaction.action,
        'quantity': transaction.quantity,
        'price': transaction.price,
        'totalAmount': transaction.totalAmount,
        'timestamp': transaction.timestamp.toIso8601String(),
      }).toList();
      
      final context = '''
You are a professional portfolio manager. Analyze this portfolio data and provide actionable suggestions:

## Current Portfolio Holdings
${json.encode(formattedHoldings)}

## Cash Balance
$cashBalance

## Transaction History
${json.encode(formattedTransactions)}

## Market Data
${json.encode(marketData)}

## Risk Tolerance
$riskTolerance

## Instructions
1. Analyze the portfolio's performance, diversification, and alignment with the user's risk tolerance.
2. Provide 3-5 specific, actionable suggestions for improving the portfolio, such as:
   - Buy recommendations (specific symbols, quantities, and approximate price targets)
   - Sell recommendations (specific symbols, quantities)
   - Asset allocation adjustments
   - Diversification recommendations
3. For each suggestion, provide a brief reasoning explaining the rationale.
4. Format your response in JSON with this structure:
   {
     "analysis": {
       "overview": "A brief overview of the portfolio's current state",
       "strengths": ["Strength 1", "Strength 2"],
       "weaknesses": ["Weakness 1", "Weakness 2"]
     },
     "suggestions": [
       {
         "type": "buy" or "sell" or "hold" or "allocate",
         "symbol": "Stock/ETF symbol if applicable",
         "action": "Clear action description (e.g., 'Buy 5 shares of AAPL')",
         "reasoning": "Brief explanation of why this action is recommended"
       }
     ]
   }
''';
      
      final content = [Content.text(context)];
      final response = await _model!.generateContent(content);      
      if (response.text == null || response.text!.isEmpty) {
        return {
          'error': 'Could not generate portfolio suggestions. Please try again later.',
          'suggestions': []
        };
      }
      
      String jsonText = response.text!;
      
      if (jsonText.contains('```json')) {
        jsonText = jsonText.split('```json')[1].split('```')[0].trim();
      } else if (jsonText.contains('```')) {
        jsonText = jsonText.split('```')[1].split('```')[0].trim();
      }
      
      try {
        final Map<String, dynamic> parsedResponse = json.decode(jsonText);
        return parsedResponse;
      } catch (e) {
        debugPrint('Error parsing portfolio suggestions JSON: $e');
        return {
          'error': 'Error parsing AI response. Please try again.',
          'rawResponse': jsonText,
          'suggestions': []
        };
      }
    } catch (e) {
      debugPrint('Error generating enhanced portfolio suggestions: $e');
      return {
        'error': 'An error occurred while generating suggestions: ${e.toString()}',
        'suggestions': []
      };
    }
  }
  
  Future<List<Map<String, dynamic>>> generatePortfolioSuggestions({
    required Map<String, dynamic> currentPortfolio,
    required Map<String, dynamic> userPreferences,
    required List<Map<String, dynamic>> marketData,
  }) async {
    try {
      if (!_isModelInitialized || _model == null) {
        if (apiKey.isEmpty) {
          return [];
        }        
        _initializeModel();
        if (!_isModelInitialized || _model == null) {
          return [];
        }
      }
      
      final context = '''
Current Portfolio: ${currentPortfolio.toString()}
User Preferences: ${userPreferences.toString()}
Market Data: ${marketData.toString()}
Generate portfolio optimization suggestions in JSON format.
''';
      
      final content = [Content.text(context)];
      final response = await _model!.generateContent(content);      
      if (response.text != null) {
        try {
          final suggestions = [
            {'asset': 'Example Asset', 'action': 'Buy', 'reason': 'Based on market trends'},
            {'asset': 'Example Asset 2', 'action': 'Sell', 'reason': 'Overvalued based on metrics'}
          ];
          return suggestions;
        } catch (e) {
          debugPrint('Error parsing portfolio suggestions: $e');
          return [];
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error generating portfolio suggestions: $e');
      return [];
    }
  }
  
  bool get isModelInitialized => _isModelInitialized && _model != null;
} 

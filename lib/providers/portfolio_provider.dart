import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/holding.dart';
import '../models/transaction.dart';
import '../services/market_data_service.dart';

class PortfolioProvider extends ChangeNotifier {
  final MarketDataService _marketDataService;
  List<Holding> _holdings = [];
  List<Transaction> _transactions = [];
  double _cashBalance = 10000000.0; // Starting with 10 say
  bool _isLoading = true;
  String _error = '';
  
  // Getters
  List<Holding> get holdings => _holdings;
  List<Transaction> get transactions => _transactions;
  double get cashBalance => _cashBalance;
  bool get isLoading => _isLoading;
  String get error => _error;
  bool get hasError => _error.isNotEmpty;
  
  // Const
  static const String _transactionsKey = 'transactions';
  static const String _holdingsKey = 'holdings';
  static const String _cashBalanceKey = 'cash_balance';
  
  // Constructor
  PortfolioProvider({required MarketDataService marketDataService}) 
      : _marketDataService = marketDataService {
    _loadData();
  }
  
  // Load data
  Future<void> _loadData() async {
    try {
      _setLoading(true);
      _clearError();
      
      final prefs = await SharedPreferences.getInstance();
      
      // Load transactions
      final transactionsJson = prefs.getString(_transactionsKey);
      if (transactionsJson != null) {
        _transactions = Transaction.listFromJson(transactionsJson);
      }
      
      // Load cash balance
      final cashBalance = prefs.getDouble(_cashBalanceKey);
      if (cashBalance != null) {
        _cashBalance = cashBalance;
      }
      
      // zasna
      if (_transactions.isEmpty) {
        addSampleHoldings();
      }
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to load portfolio data: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_transactionsKey, Transaction.listToJson(_transactions));
      
      await prefs.setDouble(_cashBalanceKey, _cashBalance);
    } catch (e) {
      print('Error saving portfolio data: $e');
      //  error state bitgii hii UI ajilahgu
    }
  }
  
  Future<bool> buyStock(String symbol, double quantity, double price) async {
    if (quantity <= 0 || price <= 0) {
      return false;
    }
    
    final totalCost = quantity * price;
    
    if (totalCost > _cashBalance) {
      return false;
    }
    
    try {
      _cashBalance -= totalCost;
      
      // Check if the user already owns this stock
      final existingHoldingIndex = _holdings.indexWhere((h) => h.symbol == symbol);
      
      if (existingHoldingIndex >= 0) {
        // Update existing holding
        final existingHolding = _holdings[existingHoldingIndex];
        final newQuantity = existingHolding.quantity + quantity;
        final newAverageCost = ((existingHolding.totalCost + totalCost) / newQuantity);
        _holdings[existingHoldingIndex] = existingHolding.copyWith(
          quantity: newQuantity,
          averageCost: newAverageCost,
        );
      } else {
        // Add new holding
        _holdings.add(Holding(
          symbol: symbol,
          quantity: quantity,
          averageCost: price,
          currentPrice: price,
        ));
      }
      
      // Record transaction
      final transaction = Transaction(
        symbol: symbol,
        action: 'buy',
        quantity: quantity,
        price: price,
        totalAmount: totalCost,
        timestamp: DateTime.now(),
      );
      
      _transactions.add(transaction);
      
      // Save data to storage
      await _saveData();
      
      notifyListeners();
      return true;
    } catch (e) {
      print('Error buying stock: $e');
      return false;
    }
  }
  
  // Sell stock
  Future<bool> sellStock(String symbol, double quantity, double price) async {
    if (quantity <= 0 || price <= 0) {
      return false;
    }
    
    // Find the holding
    final existingHoldingIndex = _holdings.indexWhere((h) => h.symbol == symbol);
    
    if (existingHoldingIndex < 0) {
      return false; // User doesn't own this stock
    }
    
    final existingHolding = _holdings[existingHoldingIndex];
    
    // Check if user has enough shares to sell
    if (existingHolding.quantity < quantity) {
      return false;
    }
    
    try {
      final totalSaleAmount = quantity * price;
      
      // Update cash balance
      _cashBalance += totalSaleAmount;
      
      // Update holdings
      final remainingQuantity = existingHolding.quantity - quantity;
      
      if (remainingQuantity > 0) {
        // Update the holding with reduced quantity
        _holdings[existingHoldingIndex] = existingHolding.copyWith(
          quantity: remainingQuantity,
        );
      } else {
        // Remove the holding if no shares left
        _holdings.removeAt(existingHoldingIndex);
      }
      
      // Record transaction
      final transaction = Transaction(
        symbol: symbol,
        action: 'sell',
        quantity: quantity,
        price: price,
        totalAmount: totalSaleAmount,
        timestamp: DateTime.now(),
      );
      
      _transactions.add(transaction);
      
      // Save data to storage
      await _saveData();
      
      notifyListeners();
      return true;
    } catch (e) {
      print('Error selling stock: $e');
      return false;
    }
  }
  
  // Add cash to account
  Future<void> addCash(double amount) async {
    if (amount <= 0) return;
    
    try {
      _cashBalance += amount;
      
      // Record transaction
      final transaction = Transaction(
        symbol: 'CASH',
        action: 'deposit',
        quantity: 1,
        price: amount,
        totalAmount: amount,
        timestamp: DateTime.now(),
      );
      
      _transactions.add(transaction);
      
      // Save data to storage
      await _saveData();
      
      notifyListeners();
    } catch (e) {
      print('Error adding cash: $e');
    }
  }
  
  // Get transactions for a specific symbol
  List<Transaction> getTransactionsForSymbol(String symbol) {
    return _transactions.where((t) => t.symbol == symbol).toList();
  }
  
  // Get recent transactions - last 30 days by default
  List<Transaction> getRecentTransactions({int days = 30}) {
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    return _transactions
        .where((t) => t.timestamp.isAfter(cutoffDate))
        .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Latest first
  }
  
  // Get current portfolio value
  Future<double> getTotalPortfolioValue() async {
    double totalValue = _cashBalance;
    
    // This could be optimized to batch fetch current prices
    for (var holding in _holdings) {
      try {
        // In a real app, mse gees api ogwol fetch hiine
        // For now, we'll use a mock price (current price = average cost * random factor)
        final currentPrice = holding.averageCost * (0.9 + (0.2 * (DateTime.now().millisecondsSinceEpoch % 100) / 100));
        totalValue += holding.quantity * currentPrice;
      } catch (e) {
        totalValue += holding.totalCost;
      }
    }
    
    return totalValue;
  }
  
  Map<String, double> getPortfolioPerformance() {
    // This would involve a more complex calculation in a real app
    // For our demo, we'll return mock performance data
    return {
      'daily': (_getRandomPerformance() * 0.01), // e.g., 0.02 (2%)
      'weekly': (_getRandomPerformance() * 0.03),
      'monthly': (_getRandomPerformance() * 0.05),
      'yearly': (_getRandomPerformance() * 0.12),
    };
  }
  
  double _getRandomPerformance() {
    final base = DateTime.now().millisecond % 10;
    if (base < 3) return -1.0 * (base + 1);  // 30% chance negative
    return base / 2.0;  // 70% chance positive
  }
  
  // Add sample holdings for demonstration purposes
  void addSampleHoldings() {
    _holdings = [
      Holding(
        symbol: 'AARD',
        quantity: 10,
        averageCost: 2450.0,
        sector: 'Technology',
        currentPrice: 2474.0,
      ),
      Holding(
        symbol: 'ADB',
        quantity: 10,
        averageCost: 100.0,
        sector: 'Technology',
        currentPrice: 102.00,
      ),
      Holding(
        symbol: 'APU',
        quantity: 10,
        averageCost: 978.85,
        sector: 'Technology',
        currentPrice: 976.79,
      ),
      Holding(
        symbol: 'BODI',
        quantity: 10,
        averageCost: 82.0,
        sector: 'Consumer Cyclical',
        currentPrice: 80.0,
      ),
      Holding(
        symbol: 'SUU',
        quantity: 10,
        averageCost: 619.62,
        sector: 'Financials',
        currentPrice: 624.0,
      ),
      Holding(
        symbol: 'GLMT',
        quantity: 8,
        averageCost: 1044.0,
        sector: 'Financials',
        currentPrice: 1040.0,
      ),
    ];
    
    // Create corresponding transactions for these holdings
    _transactions = [
      Transaction(
        symbol: 'AARD',
        action: 'buy',
        quantity: 10,
        price: 2450.0,
        totalAmount: 5408164.0,
        timestamp: DateTime.now().subtract(Duration(days: 60)),
      ),
      Transaction(
        symbol: 'ADB',
        action: 'buy',
        quantity: 10,
        price: 100.0,
        totalAmount: 716700.0,
        timestamp: DateTime.now().subtract(Duration(days: 45)),
      ),
      Transaction(
        symbol: 'APU',
        action: 'buy',
        quantity: 10,
        price: 978.85,
        totalAmount: 18043142.05,
        timestamp: DateTime.now().subtract(Duration(days: 30)),
      ),
      Transaction(
        symbol: 'BODI',
        action: 'buy',
        quantity: 10,
        price: 82.0,
        totalAmount: 480.0,
        timestamp: DateTime.now().subtract(Duration(days: 25)),
      ),
      Transaction(
        symbol: 'GAZR',
        action: 'buy',
        quantity: 10,
        price: 45.0,
        totalAmount: 10.0,
        timestamp: DateTime.now().subtract(Duration(days: 15)),
      ),
      Transaction(
        symbol: 'GLMT',
        action: 'buy',
        quantity: 10,
        price: 1030.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 60)),
      ),
      Transaction(
        symbol: 'GOV',
        action: 'buy',
        quantity: 10,
        price: 267.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 45)),
      ),
      Transaction(
        symbol: 'INV',
        action: 'buy',
        quantity: 10,
        price: 9580.85,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 30)),
      ),
      Transaction(
        symbol: 'KHAN',
        action: 'buy',
        quantity: 10,
        price: 1070.0,
        totalAmount: 30.0,
        timestamp: DateTime.now().subtract(Duration(days: 25)),
      ),
      Transaction(
        symbol: 'LEND',
        action: 'buy',
        quantity: 10,
        price: 147.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 15)),
      ),
      Transaction(
        symbol: 'MFC',
        action: 'buy',
        quantity: 10,
        price: 81.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 60)),
      ),
      Transaction(
        symbol: 'MIK',
        action: 'buy',
        quantity: 10,
        price: 12000.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 45)),
      ),
      Transaction(
        symbol: 'MNDL',
        action: 'buy',
        quantity: 10,
        price: 70.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 25)),
      ),
      Transaction(
        symbol: 'MSE',
        action: 'buy',
        quantity: 10,
        price: 288.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 15)),
      ),
      Transaction(
        symbol: 'NEH',
        action: 'buy',
        quantity: 10,
        price: 24.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 60)),
      ),
      Transaction(
        symbol: 'SBM',
        action: 'buy',
        quantity: 10,
        price: 100.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 45)),
      ),
      Transaction(
        symbol: 'SUU',
        action: 'buy',
        quantity: 10,
        price: 609.0,
        totalAmount: 20.00,
        timestamp: DateTime.now().subtract(Duration(days: 30)),
      ),
      Transaction(
        symbol: 'TCK',
        action: 'buy',
        quantity: 10,
        price: 82.0,
        totalAmount: 40.0,
        timestamp: DateTime.now().subtract(Duration(days: 25)),
      ),
      Transaction(
        symbol: 'TDB',
        action: 'buy',
        quantity: 10,
        price: 23880.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 15)),
      ),
      Transaction(
        symbol: 'TTL',
        action: 'buy',
        quantity: 10,
        price: 29440.0,
        totalAmount: 20.0,
        timestamp: DateTime.now().subtract(Duration(days: 25)),
      ),
      Transaction(
        symbol: 'TUM',
        action: 'buy',
        quantity: 10,
        price: 360.0,
        totalAmount: 30.0,
        timestamp: DateTime.now().subtract(Duration(days: 15)),
      ),
      Transaction(
        symbol: 'XAC',
        action: 'buy',
        quantity: 10,
        price: 850.0,
        totalAmount: 30.0,
        timestamp: DateTime.now().subtract(Duration(days: 15)),
      ),
    ];
    
    // Update cash balance (starting with initial $10,000 minus the purchases)
    _cashBalance = 10000.0 - 1800.0 - 1650.0 - 1080.0 - 480.0 - 1015.0 - 960.0;
    
    // Notify listeners about the change
    notifyListeners();
  }
  
  // Clear all portfolio data (for testing/reset)
  Future<void> clearPortfolioData() async {
    try {
      _holdings = [];
      _transactions = [];
      _cashBalance = 10000.0;
      
      // Save empty data to storage
      await _saveData();
      
      notifyListeners();
    } catch (e) {
      print('Error clearing portfolio data: $e');
    }
  }
  
  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void _setError(String errorMessage) {
    _error = errorMessage;
    notifyListeners();
  }
  
  void _clearError() {
    _error = '';
    notifyListeners();
  }
} 
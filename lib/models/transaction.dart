import 'dart:convert';

class Transaction {
  final String symbol;
  final String action; // 'buy' or 'sell'
  final double quantity;
  final double price;
  final double totalAmount;
  final DateTime timestamp;
  
  Transaction({
    required this.symbol,
    required this.action,
    required this.quantity,
    required this.price,
    required this.totalAmount,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'action': action,
      'quantity': quantity,
      'price': price,
      'totalAmount': totalAmount,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      symbol: json['symbol'] as String,
      action: json['action'] as String,
      // Firestore/JSON бүхэл тоог int болгож буцаадаг тул num-аас хөрвүүлнэ
      quantity: (json['quantity'] as num).toDouble(),
      price: (json['price'] as num).toDouble(),
      totalAmount: (json['totalAmount'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
  
  static List<Transaction> listFromJson(String jsonStr) {
    final List<dynamic> jsonList = json.decode(jsonStr);
    return jsonList.map((item) => Transaction.fromJson(item)).toList();
  }
  
  static String listToJson(List<Transaction> transactions) {
    final List<Map<String, dynamic>> jsonList = 
        transactions.map((t) => t.toJson()).toList();
    return json.encode(jsonList);
  }
} 
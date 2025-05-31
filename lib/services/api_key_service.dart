import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiKeyService {
  static final _storage = FlutterSecureStorage();
  
  static Future<String> getGeminiApiKey() async {
    try {
      String? apiKey = await _storage.read(key: 'gemini_api_key');
      
      if (apiKey == null || apiKey.isEmpty) {
        return 'API key';
      }
      
      return apiKey;
    } catch (e) {
      print('Error retrieving Gemini API key: $e');
      return '';
    }
  }
    static Future<bool> saveGeminiApiKey(String apiKey) async {
    try {
      await _storage.write(key: 'gemini_api_key', value: apiKey);
      return true;
    } catch (e) {
      print('Error saving Gemini API key: $e');
      return false;
    }
  }
  
  static Future<bool> validateGeminiApiKey(String apiKey) async {
    if (apiKey.isEmpty) {
      return false;
    }
    
    try {
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
      final response = await http.get(url).timeout(Duration(seconds: 10));
            if (response.statusCode == 200) {
        return true;
      }
      
      print('API key validation failed. Status code: ${response.statusCode}');
      print('Response body: ${response.body}');
      
      return false;
    } catch (e) {
      print('Error validating Gemini API key: $e');
      return false;
    }
  }
} 

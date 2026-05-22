import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiKeyService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _keyName = 'gemini_api_key';

  static Future<String> getGeminiApiKey() async {
    try {
      final apiKey = await _storage.read(key: _keyName);

      if (apiKey == null || apiKey.isEmpty) {
        return '';
      }

      return apiKey;
    } catch (e) {
      _log('Error retrieving API key: $e');
      return '';
    }
  }

  static Future<bool> saveGeminiApiKey(String apiKey) async {
    try {
      await _storage.write(key: _keyName, value: apiKey);
      return true;
    } catch (e) {
      _log('Error saving API key: $e');
      return false;
    }
  }

  static Future<bool> validateGeminiApiKey(String apiKey) async {
    if (apiKey.isEmpty) return false;

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      );

      final response = await http.get(url).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) return true;

      _log('Validation failed: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      _log('Validation error: $e');
      return false;
    }
  }

  static void _log(String msg) {
    // CI friendly logging
    // ignore: avoid_print
    print(msg);
  }
}

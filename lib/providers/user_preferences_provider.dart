import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserPreferencesProvider extends ChangeNotifier {
  String _riskTolerance = 'Moderate';
  bool _isDarkMode = false;
  bool _isLoading = true;
  String _error = '';

  String get riskTolerance => _riskTolerance;
  bool get isDarkMode => _isDarkMode;
  bool get isLoading => _isLoading;
  String get error => _error;
  bool get hasError => _error.isNotEmpty;

  static const String _riskToleranceKey = 'risk_tolerance';
  static const String _darkModeKey = 'dark_mode';

  static const List<String> riskToleranceOptions = [
    'Conservative',
    'Moderately Conservative',
    'Moderate',
    'Moderately Aggressive',
    'Aggressive'
  ];

  UserPreferencesProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      _setLoading(true);
      _clearError();

      final prefs = await SharedPreferences.getInstance();

      final riskTolerance = prefs.getString(_riskToleranceKey);
      if (riskTolerance != null && riskToleranceOptions.contains(riskTolerance)) {
        _riskTolerance = riskTolerance;
      }
      final isDarkMode = prefs.getBool(_darkModeKey);
      if (isDarkMode != null) {
        _isDarkMode = isDarkMode;
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to load preferences: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_riskToleranceKey, _riskTolerance);

      await prefs.setBool(_darkModeKey, _isDarkMode);
    } catch (e) {
      print('Error saving preferences: $e');
    }
  }

  Future<void> setRiskTolerance(String riskTolerance) async {
    if (!riskToleranceOptions.contains(riskTolerance)) {
      _setError('Invalid risk tolerance value');
      return;
    }

    try {
      _riskTolerance = riskTolerance;
      await _savePreferences();
      notifyListeners();
    } catch (e) {
      _setError('Failed to set risk tolerance: $e');
    }
  }
  Future<void> toggleDarkMode() async {
    try {
      _isDarkMode = !_isDarkMode;
      await _savePreferences();
      notifyListeners();
    } catch (e) {
      _setError('Failed to toggle dark mode: $e');
    }
  }
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

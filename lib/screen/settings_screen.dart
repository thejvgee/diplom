import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_state.dart';
import '../providers/user_preferences_provider.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = FlutterSecureStorage();
  bool _isLoading = true;
  bool _useMockData = false;
  final _formKey = GlobalKey<FormState>();

  // Additional settings
  bool _enableNotifications = true;
  bool _enableMarketAlerts = true;
  bool _enablePortfolioUpdates = true;
  String _refreshInterval = '15 minutes';
  String _selectedCurrency = 'MNT';
  TextEditingController _nameController = TextEditingController();
  TextEditingController _emailController = TextEditingController();

  // List of available currencies
  final List<String> _currencies = ['USD', 'EUR', 'MNT'];

  // List of refresh intervals
  final List<String> _refreshIntervals = [
    '5 minutes',
    '15 minutes',
    '30 minutes',
    '1 hour',
    'Manual'
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load mock data preference
      String? useMockDataStr = await _storage.read(key: 'use_mock_data');
      _useMockData = useMockDataStr == 'true';

      // Load notification preferences
      _enableNotifications = prefs.getBool('enable_notifications') ?? true;
      _enableMarketAlerts = prefs.getBool('enable_market_alerts') ?? true;
      _enablePortfolioUpdates =
          prefs.getBool('enable_portfolio_updates') ?? true;

      // Load refresh interval
      _refreshInterval = prefs.getString('refresh_interval') ?? '15 minutes';

      // Load currency
      _selectedCurrency = prefs.getString('currency') ?? 'USD';

      // Load user info
      _nameController.text = prefs.getString('userName') ?? '';
      _emailController.text = prefs.getString('userEmail') ?? '';
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load settings: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      // Clear secure storage
      final _storage = FlutterSecureStorage();
      await _storage.deleteAll();

      // Clear shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Navigate to login screen and remove all previous routes
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Гарахад алдаа гарлаа: $e')),
      );
    }
  }

  Future<void> _toggleMockData(bool value) async {
    try {
      await _storage.write(key: 'use_mock_data', value: value.toString());
      setState(() => _useMockData = value);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? 'Mock data enabled. App will use offline data.'
              : 'Mock data disabled. App will use real data when available.'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update setting: $e')),
      );
    }
  }

  Future<bool> _checkConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // Save notification preferences
  Future<void> _saveNotificationPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enable_notifications', _enableNotifications);
      await prefs.setBool('enable_market_alerts', _enableMarketAlerts);
      await prefs.setBool('enable_portfolio_updates', _enablePortfolioUpdates);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Notification preferences saved')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save notification preferences: $e')),
      );
    }
  }

  // Save refresh interval
  Future<void> _saveRefreshInterval(String interval) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('refresh_interval', interval);
      setState(() => _refreshInterval = interval);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data refresh interval updated')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save refresh interval: $e')),
      );
    }
  }

  // Save currency
  Future<void> _saveCurrency(String currency) async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.setCurrency(currency);
      setState(() => _selectedCurrency = currency);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Валют шинэчлэгдлээ $currency')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Валют хадгалахад алдаа гарлаа: $e')),
      );
    }
  }

  // Save user profile

  Future<void> _saveUserProfile() async {
    try {
      if (_formKey.currentState!.validate()) {
        final appState = Provider.of<AppState>(context, listen: false);
        await appState.updateUserInfo(
            _nameController.text, _emailController.text);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Профайл амжилттай шинэчлэгдлээ')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Профайл шинэчлэгдэхэд алдаа гарлаа: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Settings')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: Consumer2<AppState, UserPreferencesProvider>(
        builder: (context, appState, userPreferences, _) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Profile Section
                  Text(
                    'Хэрэглэгчийн мэдээлэл',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),

                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Theme.of(context).primaryColor,
                                radius: 30,
                                child: Icon(Icons.person,
                                    size: 30, color: Colors.white),
                              ),
                              SizedBox(width: 16.0),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Хувийн мэдээлэл',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    SizedBox(height: 4.0),
                                    Text(
                                      'Профайлын details шинэчлэх',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 24.0),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Бүтэн нэр',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Нэрээ оруулна уу';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: 16.0),
                          TextFormField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: 'Email хаяг',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                  .hasMatch(value)) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: 16.0),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _saveUserProfile,
                              icon: Icon(Icons.save),
                              label: Text('Профайл хадгалах'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.0),

                  // Appearance Settings
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),

                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            title: Text('Dark Mode'),
                            subtitle: Text(userPreferences.isDarkMode
                                ? 'Using dark theme'
                                : 'Using light theme'),
                            value: userPreferences.isDarkMode,
                            onChanged: (value) {
                              userPreferences.toggleDarkMode();
                            },
                            secondary: Icon(
                              userPreferences.isDarkMode
                                  ? Icons.dark_mode
                                  : Icons.light_mode,
                              color: userPreferences.isDarkMode
                                  ? Colors.amber
                                  : Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.0),

                  // Security Settings
                  Text(
                    'Security',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),

                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            title: Text('Biometric Authentication'),
                            subtitle: Text(appState.isBiometricEnabled
                                ? 'Enabled for app access'
                                : 'Disabled'),
                            value: appState.isBiometricEnabled,
                            onChanged: (value) async {
                              await appState.toggleBiometric();
                              setState(() {});
                            },
                            secondary: Icon(
                              Icons.fingerprint,
                              color: appState.isBiometricEnabled
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.0),

                  // Notification Settings
                  Text(
                    'Мэдэгдэл',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),

                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            title: Text('Enable Notifications'),
                            subtitle: Text(_enableNotifications
                                ? 'Та аппликейшнаас мэдэгдэл хүлээн авах болно'
                                : 'Бүх мэдэгдэл идэвхгүй байна'),
                            value: _enableNotifications,
                            onChanged: (value) {
                              setState(() {
                                _enableNotifications = value;
                                if (!value) {
                                  _enableMarketAlerts = false;
                                  _enablePortfolioUpdates = false;
                                }
                              });
                              _saveNotificationPreferences();
                            },
                            secondary: Icon(
                              _enableNotifications
                                  ? Icons.notifications_active
                                  : Icons.notifications_off,
                              color: _enableNotifications
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                          ),
                          Divider(),
                          SwitchListTile(
                            title: Text('Зах зээлийн сэрэмжлүүлэг'),
                            subtitle: Text('Үнийн өөрчлөлт, зах зээлийн мэдээ'),
                            value: _enableMarketAlerts && _enableNotifications,
                            onChanged: _enableNotifications
                                ? (value) {
                                    setState(() => _enableMarketAlerts = value);
                                    _saveNotificationPreferences();
                                  }
                                : null,
                            secondary: Icon(
                              Icons.trending_up,
                              color:
                                  (_enableMarketAlerts && _enableNotifications)
                                      ? Colors.blue
                                      : Colors.grey,
                            ),
                          ),
                          SwitchListTile(
                            title: Text('Багцын шинэчлэлт'),
                            subtitle: Text(
                                'Таны holding болон гүйцэтгэлд гарсан өөрчлөлтүүд'),
                            value:
                                _enablePortfolioUpdates && _enableNotifications,
                            onChanged: _enableNotifications
                                ? (value) {
                                    setState(
                                        () => _enablePortfolioUpdates = value);
                                    _saveNotificationPreferences();
                                  }
                                : null,
                            secondary: Icon(
                              Icons.account_balance_wallet,
                              color: (_enablePortfolioUpdates &&
                                      _enableNotifications)
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.0),

                  // Preferences
                  Text(
                    'Сонголтууд',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),

                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.currency_exchange,
                                        color: Colors.grey.shade600),
                                    SizedBox(width: 16.0),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Валют',
                                            style: TextStyle(fontSize: 16.0),
                                          ),
                                          SizedBox(height: 4.0),
                                          Text(
                                            'Ашиглах валютаа сонгоно уу',
                                            style: TextStyle(
                                                fontSize: 14.0,
                                                color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12.0, vertical: 4.0),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8.0),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    color: Theme.of(context).cardColor,
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedCurrency,
                                      isExpanded: true,
                                      icon: Icon(Icons.arrow_drop_down),
                                      onChanged: (String? newValue) {
                                        if (newValue != null) {
                                          _saveCurrency(newValue);
                                        }
                                      },
                                      items: _currencies
                                          .map<DropdownMenuItem<String>>(
                                              (String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Divider(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.shield,
                                        color: Colors.grey.shade600),
                                    SizedBox(width: 16.0),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Эрсдлийн түвшин',
                                            style: TextStyle(fontSize: 16.0),
                                          ),
                                          SizedBox(height: 4.0),
                                          Text(
                                            'Хөрөнгө оруулалтын эрсдлийн профилийг тохируулах',
                                            style: TextStyle(
                                                fontSize: 14.0,
                                                color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12.0, vertical: 4.0),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8.0),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    color: Theme.of(context).cardColor,
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: userPreferences.riskTolerance,
                                      isExpanded: true,
                                      icon: Icon(Icons.arrow_drop_down),
                                      onChanged: (String? newValue) {
                                        if (newValue != null) {
                                          userPreferences
                                              .setRiskTolerance(newValue);
                                        }
                                      },
                                      items: UserPreferencesProvider
                                          .riskToleranceOptions
                                          .map<DropdownMenuItem<String>>(
                                              (String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Divider(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.update,
                                        color: Colors.grey.shade600),
                                    SizedBox(width: 16.0),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Өгөгдөл рэфреш интервал',
                                            style: TextStyle(fontSize: 16.0),
                                          ),
                                          SizedBox(height: 4.0),
                                          Text(
                                            'Та мэдээллийг хэдэн минут тутам шинэчлэх вэ',
                                            style: TextStyle(
                                                fontSize: 14.0,
                                                color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12.0, vertical: 4.0),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8.0),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    color: Theme.of(context).cardColor,
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _refreshInterval,
                                      isExpanded: true,
                                      icon: Icon(Icons.arrow_drop_down),
                                      onChanged: (String? newValue) {
                                        if (newValue != null) {
                                          _saveRefreshInterval(newValue);
                                        }
                                      },
                                      items: _refreshIntervals
                                          .map<DropdownMenuItem<String>>(
                                              (String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.0),

                  // Data Settings
                  Text(
                    'Data Settings',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),

                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mock Data Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 8.0),
                          Text(
                            'Идэвхжүүлсэн үед апп нь API дуудлага хийхийн оронд дотооддоо үүсгэсэн хуурамч өгөгдлийг ашиглана. Энэ нь тест хийх эсвэл интернетийн холболт хязгаарлагдмал үед хэрэг болно.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          SizedBox(height: 16.0),
                          SwitchListTile(
                            title: Text('Use Mock Data'),
                            subtitle: Text(_useMockData
                                ? 'Using offline demo data'
                                : 'Using real-time market data when available'),
                            value: _useMockData,
                            onChanged: _toggleMockData,
                            secondary: Icon(
                              _useMockData ? Icons.cloud_off : Icons.cloud_done,
                              color:
                                  _useMockData ? Colors.orange : Colors.green,
                            ),
                          ),
                          if (_useMockData)
                            Container(
                              padding: EdgeInsets.all(8.0),
                              color: Colors.orange.shade50,
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: Colors.orange),
                                  SizedBox(width: 8.0),
                                  Expanded(
                                    child: Text(
                                      'Mock data горим идэвхижсэн. The app will show simulated data.',
                                      style: TextStyle(
                                          color: Colors.orange.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.0),

                  // Network Status
                  Text(
                    'Network Status',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),

                  FutureBuilder<bool>(
                    future: _checkConnectivity(),
                    builder: (context, snapshot) {
                      bool isConnected = snapshot.data ?? false;

                      return Card(
                        elevation: 2,
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(
                                isConnected ? Icons.wifi : Icons.wifi_off,
                                color: isConnected ? Colors.green : Colors.red,
                                size: 36,
                              ),
                              SizedBox(width: 16.0),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isConnected ? 'Connected' : 'Offline',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isConnected
                                            ? Colors.green
                                            : Colors.red,
                                        fontSize: 18,
                                      ),
                                    ),
                                    SizedBox(height: 4.0),
                                    Text(
                                      isConnected
                                          ? 'Та интернетэд холболттой байна. Бодит цагийн өгөгдлийг татаж авах боломжтой.'
                                          : 'Интернэт холболтгүй байна. Апп нь кэш эсвэл mock data ашиглах болно.',
                                      style: TextStyle(
                                        color: isConnected
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: 24.0),

                  // About
                  Text(
                    'About',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _logout,
                          icon: Icon(Icons.logout),
                          label: Text('Гарах'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.0),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).primaryColor,
                              child: Icon(Icons.bar_chart, color: Colors.white),
                            ),
                            title: Text(
                              'Хөрөнгө оруулалтын зөвлөх',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            subtitle: Text('Version 1.0.0'),
                          ),
                          Divider(),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'ШУТИС ДИПЛОМНЫ АЖИЛ.',
                            ),
                          ),
                          SizedBox(height: 8.0),
                          Text(
                            '© 2023 4 23',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.0),

                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'Хөрөнгө оруулалтын зөвлөх',
                          applicationVersion: '1.0.0',
                          applicationLegalese: '© 2025',
                          children: [
                            SizedBox(height: 16.0),
                            Text(
                              'Хөрөнгө оруулалтын зөвлөх апп.',
                            ),
                          ],
                        );
                      },
                      icon: Icon(Icons.info_outline),
                      label: Text('About this app'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

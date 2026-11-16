import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai_engine/risk_profile.dart';
import '../providers/app_state.dart';
import '../providers/mse_market_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/user_preferences_provider.dart';
import 'auth_gate.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = FlutterSecureStorage();
  bool _isLoading = true;
  final _formKey = GlobalKey<FormState>();

  // Ханшийн шинэчлэлийн давтамж (MseMarketProvider-т шууд нөлөөлнө)
  String _refreshInterval = MseMarketProvider.defaultRefreshOption;
  TextEditingController _nameController = TextEditingController();
  TextEditingController _emailController = TextEditingController();

  final List<String> _refreshIntervals =
      MseMarketProvider.refreshOptions.keys.toList();

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

      final saved = prefs.getString(MseMarketProvider.refreshPrefKey);
      _refreshInterval = MseMarketProvider.refreshOptions.containsKey(saved)
          ? saved!
          : MseMarketProvider.defaultRefreshOption;

      // Load user info
      _nameController.text = prefs.getString('userName') ?? '';
      _emailController.text = prefs.getString('userEmail') ?? '';
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load settings: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      // Firebase-ээс гарна (өмнө нь зөвхөн утасны санг цэвэрлэдэг байсан тул
      // хэрэглэгч нэвтэрсэн хэвээр үлддэг байв)
      await FirebaseAuth.instance.signOut();

      await _storage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Гарахад алдаа гарлаа: $e')),
      );
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Цуцлах')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Симуляцийн дансыг анхны 10 сая төгрөгтэй болгож шинээр эхлүүлнэ.
  Future<void> _resetPortfolio() async {
    if (!await _confirm(
        'Багцыг шинээр эхлүүлэх үү?',
        'Бүх хувьцаа, гүйлгээний түүх устаж, данс анхны '
            '10,000,000₮ болно. Энэ үйлдлийг буцаах боломжгүй.',
        'Шинээр эхлүүлэх')) return;
    if (!mounted) return;
    await context.read<PortfolioProvider>().resetPortfolio();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Багц шинээр эхэллээ')));
  }

  /// Бүртгэл болон бүх өгөгдлийг устгана (Google Play-ийн шаардлага).
  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Firebase бүртгэл устгахад сүүлийн ~5 минутад нэвтэрсэн байх шаардлагатай.
    // Өгөгдлийг устгаад бүртгэл устахгүй үлдэхээс сэргийлж урьдчилан шалгана.
    final lastSignIn = user.metadata.lastSignInTime;
    if (lastSignIn == null ||
        DateTime.now().difference(lastSignIn) > Duration(minutes: 5)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Аюулгүй байдлын үүднээс гараад дахин нэвтэрч орсны '
            'дараа бүртгэлээ устгана уу.'),
        duration: Duration(seconds: 5),
      ));
      return;
    }

    if (!await _confirm(
        'Бүртгэлээ устгах уу?',
        'Таны бүртгэл, багц, гүйлгээний түүх, AI чатын түүх бүгд бүрмөсөн '
            'устана. Энэ үйлдлийг буцаах боломжгүй.',
        'Бүрмөсөн устгах')) return;
    if (!mounted) return;

    final portfolio = context.read<PortfolioProvider>();
    try {
      final db = FirebaseFirestore.instance;
      final chats = await db
          .collection('chat_history')
          .where('userId', isEqualTo: user.uid)
          .get();
      final batch = db.batch();
      for (final doc in chats.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      await portfolio.deleteAllData();
      await db.collection('users').doc(user.uid).delete();
      await user.delete();

      await _storage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.code == 'requires-recent-login'
            ? 'Дахин нэвтэрч орсны дараа бүртгэлээ устгана уу.'
            : 'Бүртгэл устгахад алдаа гарлаа: ${e.message}'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Бүртгэл устгахад алдаа гарлаа: $e')));
    }
  }

  Future<bool> _checkConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // Save refresh interval
  Future<void> _saveRefreshInterval(String interval) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(MseMarketProvider.refreshPrefKey, interval);
      if (!mounted) return;
      context
          .read<MseMarketProvider>()
          .setRefreshInterval(MseMarketProvider.parseRefreshInterval(interval));
      setState(() => _refreshInterval = interval);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ханшийн шинэчлэлт: $interval')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Хадгалахад алдаа гарлаа: $e')),
      );
    }
  }

  Future<void> _saveUserProfile() async {
    try {
      if (_formKey.currentState!.validate()) {
        final appState = Provider.of<AppState>(context, listen: false);
        await appState.updateUserInfo(
            _nameController.text, _emailController.text);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Профайл амжилттай шинэчлэгдлээ')),
        );
      }
    } catch (e) {
      if (!mounted) return;
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
                            title: Text('Биометр түгжээ'),
                            subtitle: Text(appState.isBiometricEnabled
                                ? 'Апп нээхэд хурууны хээ/царай асууна'
                                : 'Унтраалттай'),
                            value: appState.isBiometricEnabled,
                            onChanged: (value) async {
                              if (value) {
                                final ok = await BiometricLock.confirm(
                                    'Биометр түгжээг асаахын тулд баталгаажуулна уу');
                                if (!ok) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Энэ төхөөрөмж биометр дэмжихгүй эсвэл баталгаажуулалт амжилтгүй')),
                                  );
                                  return;
                                }
                              }
                              await appState.toggleBiometric();
                              if (mounted) setState(() {});
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
                                      items: [
                                        for (final p in RiskProfile.all)
                                          DropdownMenuItem<String>(
                                            value: p.key,
                                            child: Text(p.label),
                                          ),
                                      ],
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
                                            'Ханшийн шинэчлэлт',
                                            style: TextStyle(fontSize: 16.0),
                                          ),
                                          SizedBox(height: 4.0),
                                          Text(
                                            'Арилжааны цагаар хувьцааны ханшийг хэр давтамжтай татах вэ',
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

                  // Данс
                  Text(
                    'Данс',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 16.0),
                  Card(
                    elevation: 2,
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.restart_alt),
                          title: Text('Симуляцийн багцыг шинээр эхлүүлэх'),
                          subtitle: Text('Данс анхны 10,000,000₮ болно'),
                          onTap: _resetPortfolio,
                        ),
                        Divider(height: 1),
                        ListTile(
                          leading:
                              Icon(Icons.delete_forever, color: Colors.red),
                          title: Text('Бүртгэл устгах',
                              style: TextStyle(color: Colors.red)),
                          subtitle: Text('Бүх өгөгдөл бүрмөсөн устана'),
                          onTap: _deleteAccount,
                        ),
                      ],
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
                                          : 'Интернэт холболтгүй байна. Апп нь хамгийн сүүлд хадгалсан өгөгдлийг харуулна.',
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

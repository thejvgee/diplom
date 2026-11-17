import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Апп-ын эхлэл: нэвтэрсэн (имэйл баталгаажсан) хэрэглэгчийг шууд нүүр
/// хуудас руу оруулна — апп нээх бүрт дахин нэвтрэх шаардлагагүй.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null || !user.emailVerified) return LoginScreen();
        final biometric = context.watch<AppState>().isBiometricEnabled;
        return biometric ? BiometricLock(child: HomeScreen()) : HomeScreen();
      },
    );
  }
}

/// Биометр (хурууны хээ/царай) эсвэл утасны PIN-ээр түгжээ тайлна.
/// Апп эхлэхэд болон 1 минутаас удаан далд байсны дараа асууна.
class BiometricLock extends StatefulWidget {
  final Widget child;
  const BiometricLock({super.key, required this.child});

  static const Duration relockAfter = Duration(minutes: 1);

  /// Тохиргоонд биометр асаахаас өмнө төхөөрөмж дэмжиж байгаа эсэхийг
  /// шалгаж, нэг удаа баталгаажуулна.
  static Future<bool> confirm(String reason) async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return false;
      return await auth.authenticate(localizedReason: reason);
    } catch (e) {
      debugPrint('Biometric error: $e');
      return false;
    }
  }

  @override
  State<BiometricLock> createState() => _BiometricLockState();
}

class _BiometricLockState extends State<BiometricLock> {
  late final AppLifecycleListener _lifecycle;
  bool _unlocked = false;
  bool _busy = false;
  String? _error;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        final hiddenAt = _hiddenAt;
        if (hiddenAt != null &&
            DateTime.now().difference(hiddenAt) > BiometricLock.relockAfter) {
          setState(() => _unlocked = false);
          _unlock();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy || _unlocked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await BiometricLock.confirm('Апп-ын түгжээг тайлна уу');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _unlocked = ok;
      _error = ok ? null : 'Баталгаажуулалт амжилтгүй боллоо';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64,
                  color: Theme.of(context).colorScheme.primary),
              SizedBox(height: 16),
              Text('Апп түгжигдсэн',
                  style: Theme.of(context).textTheme.titleLarge),
              if (_error != null) ...[
                SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Colors.red)),
              ],
              SizedBox(height: 24),
              ElevatedButton.icon(
                icon: Icon(Icons.fingerprint),
                label: Text('Түгжээ тайлах'),
                onPressed: _busy ? null : _unlock,
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: Text('Гарах'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

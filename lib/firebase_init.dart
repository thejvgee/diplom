import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Firebase-ийг платформоос хамааруулан эхлүүлнэ.
///
/// * Android/iOS: `google-services.json` / `GoogleService-Info.plist`-ээс.
/// * Вэб: тохиргоо (`firebase_options.dart`) repo-оос хасагдсан тул
///   1. `--dart-define=FIREBASE_WEB_API_KEY=...` өгсөн бол түүгээр
///      (дотоод хөгжүүлэлт: `--dart-define-from-file=web_config.json`), эсвэл
///   2. Firebase Hosting-ийн нөөцлөгдсөн `/__/firebase/init.json` хаягаас
///      (байршуулсан сайт дээр автоматаар ажиллана — түлхүүр build-д ордоггүй).
Future<FirebaseApp> initFirebase() async {
  if (!kIsWeb) return Firebase.initializeApp();
  return Firebase.initializeApp(options: await FirebaseWebConfig.load());
}

class FirebaseWebConfig {
  static const String apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');

  // Доорх нь нууц биш танигч (firebase.json-д ч бий). Хэрэгтэй бол
  // --dart-define-аар сольж болно.
  static const String appId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '1:464701040005:web:8b1bbfc349926d481a10ec',
  );
  static const String projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'diplom-23056',
  );
  static const String messagingSenderId = '464701040005';

  /// Firebase Hosting дээр байршуулсан сайт бүрт байдаг нөөц хаяг.
  static const String initJsonPath = '/__/firebase/init.json';

  static Future<FirebaseOptions> load({
    Future<String> Function(Uri url)? fetcher,
    Uri? base,
  }) async {
    if (apiKey.isNotEmpty) return fromDefines();
    final url = (base ?? Uri.base).resolve(initJsonPath);
    try {
      final body = await (fetcher ?? _httpGet)(url);
      return fromInitJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (e) {
      throw StateError(
        'Firebase-ийн вэб тохиргоо олдсонгүй ($url: $e). '
        'Дотоод хөгжүүлэлтэд `--dart-define-from-file=web_config.json` '
        'өгнө үү (docs/web_deploy.md).',
      );
    }
  }

  static FirebaseOptions fromDefines() => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: '$projectId.firebaseapp.com',
    storageBucket: '$projectId.firebasestorage.app',
  );

  /// `/__/firebase/init.json`-ийн хариу:
  /// `{"apiKey": ..., "appId": ..., "projectId": ..., "authDomain": ..., ...}`
  static FirebaseOptions fromInitJson(Map<String, dynamic> json) {
    String? s(String k) {
      final v = json[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    final key = s('apiKey');
    // Console дээр вэб апп hosting сайттай холбогдоогүй бол init.json-д
    // appId ирдэггүй — нууц биш танигч тул анхдагч утгыг ашиглана.
    final app = s('appId') ?? appId;
    final project = s('projectId');
    if (key == null || project == null) {
      throw const FormatException('init.json-д apiKey/projectId алга');
    }
    return FirebaseOptions(
      apiKey: key,
      appId: app,
      messagingSenderId: s('messagingSenderId') ?? messagingSenderId,
      projectId: project,
      authDomain: s('authDomain') ?? '$project.firebaseapp.com',
      storageBucket: s('storageBucket'),
      measurementId: s('measurementId'),
      databaseURL: s('databaseURL'),
    );
  }

  static Future<String> _httpGet(Uri url) async {
    final res = await http.get(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return res.body;
  }
}

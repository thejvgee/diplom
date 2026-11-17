import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../ai_engine/chat_tools.dart';
import 'api_key_service.dart';

/// AI чат (Gemini). Хариултыг апп-ын бодит өгөгдөлд тулгуурлуулна:
/// * [localAnswer] — "X төгрөгөө юунд оруулах вэ" асуултад Gemini-гүйгээр
///   апп-ын AI загвар хариулна (хувьцаа зохиохоос сэргийлнэ).
/// * [contextBuilder] — хэрэглэгчийн багц, AI дохиог Gemini-д контекст болгон өгнө.
/// * [offlineAnswer] — Gemini холбогдохгүй үед багцын бодит тойм.
/// * [toolHandler] — function calling: Gemini апп-ын AI engine-ийн функцийг
///   (багцын шинжилгээ, хувьцааны дохио, зорилгын тооцоо...) дуудаж бодит тоо авна.
class GeminiService {
  static const String _basePrompt = '''
Та бол Монголын хөрөнгийн бирж (MSE) дээр төвлөрсөн, хөрөнгө оруулалтын
симуляцийн апп-ын AI туслах. Хэрэглэгч бодит мөнгө биш, симуляцийн дансаар
хөрөнгө оруулалт сурч байна.

Хариулахдаа:
1. Монгол хэлээр, товч, ойлгомжтой бич; шууд хариултаар эхэл.
2. Хувьцаа, ханш, магадлал, хэрэглэгчийн багцын талаар зөвхөн "[АПП-ЫН БОДИТ
   ӨГӨГДӨЛ]" хэсэгт өгсөн мэдээллийг ашигла. Тэнд байхгүй хувьцаа, тоо,
   компанийн мэдээ зохиож болохгүй.
3. Ерөнхий санхүүгийн ойлголт (төрөлжилт, эрсдэл, нийлмэл хүү, төсөв)
   тайлбарлаж болно.
4. Эрсдэлийг үргэлж дурд; баталгаатай өгөөж амлахгүй.
5. Төгсгөлд нь энэ нь мэргэжлийн санхүүгийн зөвлөгөө биш гэдгийг товч сануул.
6. Хувьцааны дохио, багцын шинжилгээ, хөрөнгө хуваарилалт, зорилгын (N жилд X
   төгрөг) тооцоо, загварын гүйцэтгэл хэрэгтэй бол өгөгдсөн функцуудыг ДУУДАЖ,
   үр дүнгийн тоог ашигла. Өөрөө тооцоолж эсвэл таамаглаж болохгүй.
''';

  /// Нэг асуултад функц дуудах дээд тоо (хязгааргүй давталтаас сэргийлнэ).
  static const int maxToolRounds = 4;

  /// Gemini холбогдохгүй үеийн хариултын эхлэл (чатын дэлгэц үүгээр таньдаг).
  static const String offlinePrefix = '⚠️ AI чат одоогоор холбогдохгүй байна';

  /// Чатын дэлгэц: энэ хариулт Gemini-ээс биш (офлайн/алдаа) эсэх.
  static bool isOfflineReply(String text) => text.startsWith(offlinePrefix);

  String Function()? contextBuilder;
  String? Function(String message)? localAnswer;
  String Function(String message)? offlineAnswer;
  Map<String, Object?> Function(String name, Map<String, Object?> args)?
      toolHandler;

  GenerativeModel? _model;
  final Connectivity _connectivity = Connectivity();

  /// Gemini-ийн түлхүүр тохируулсан эсэх. Түлхүүрийг кодонд/APK-д биш, зөвхөн
  /// хэрэглэгчийн утасны нууц санд (ApiKeyService) хадгална.
  bool get hasApiKey => _model != null;

  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  /// Нууц сангаас түлхүүрийг уншиж загварыг бэлдэнэ. Тохиргоонд түлхүүр
  /// хадгалсны дараа дахин дуудна.
  Future<void> init() async {
    final apiKey = await ApiKeyService.getGeminiApiKey();
    _model = apiKey.isEmpty ? null : _createModel(apiKey);
  }

  GenerativeModel _createModel(String apiKey) => GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: apiKey,
        tools: [Tool(functionDeclarations: _declarations())],
        generationConfig: GenerationConfig(
          temperature: 0.4,
          topP: 0.7,
          topK: 40,
        ),
      );

  /// ChatTools-ийн тодорхойлолтыг Gemini-ийн FunctionDeclaration болгоно.
  static List<FunctionDeclaration> _declarations() => [
        for (final spec in ChatTools.specs)
          FunctionDeclaration(
            spec.name,
            spec.description,
            spec.params.isEmpty
                ? null
                : Schema.object(
                    properties: {
                      for (final e in spec.params.entries)
                        e.key: switch (e.value.type) {
                          'number' => Schema.number(description: e.value.description),
                          'integer' => Schema.integer(description: e.value.description),
                          _ => Schema.string(description: e.value.description),
                        },
                    },
                    requiredProperties: [
                      for (final e in spec.params.entries)
                        if (e.value.required) e.key
                    ],
                  ),
          ),
      ];

  Future<bool> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }


  /// Мэндчилгээ. Өмнө нь энд Gemini-г дуудаад хариуг нь ашигладаггүй байсан —
  /// чат нээх бүрт дэмий API зардал гаргадаг байв.
  Future<String> startChat() async =>
      'Сайн байна уу! Би таны хөрөнгө оруулалтын AI туслах. Таны багц болон '
      'MSE-ийн бодит өгөгдөл дээр тулгуурлан хариулна.';

  Future<String> sendMessage(String message) async {
    // 1. Тодорхой дүнгийн хөрөнгө оруулалт → апп-ын AI загвар хариулна
    final local = localAnswer?.call(message);
    if (local != null) {
      await _storeMessage(message, local, false);
      return local;
    }

    final model = _model;
    if (model == null) {
      return _offline(
          message, 'AI чатын түлхүүр тохируулаагүй — Тохиргоо → AI чатын түлхүүр');
    }
    if (!await _checkConnectivity()) {
      return _offline(message, 'интернэт холболт алга');
    }

    // 2. Gemini — бодит өгөгдлийн контекст + function calling
    try {
      final context = contextBuilder?.call();
      final contents = <Content>[
        Content.text(_basePrompt),
        if (context != null && context.isNotEmpty) Content.text(context),
        Content.text(message),
      ];
      GenerateContentResponse response = await model.generateContent(contents);
      for (var round = 0; round < maxToolRounds; round++) {
        final calls = response.functionCalls.toList();
        if (calls.isEmpty) break;
        contents.add(Content.model(calls));
        contents.add(Content.functionResponses([
          for (final c in calls)
            FunctionResponse(
              c.name,
              toolHandler?.call(c.name, c.args) ??
                  {'error': 'Функц одоогоор ашиглах боломжгүй'},
            ),
        ]));
        response = await model.generateContent(contents);
      }
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        return _offline(message, 'хариулт ирсэнгүй');
      }
      await _storeMessage(message, text, false);
      return text;
    } catch (e) {
      debugPrint('Gemini error: $e');
      return _offline(
          message,
          e.toString().contains('API key')
              ? 'AI чатын түлхүүр буруу байна'
              : 'AI үйлчилгээнд алдаа гарлаа');
    }
  }

  String _offline(String message, String reason) {
    final summary = offlineAnswer?.call(message);
    return '$offlinePrefix ($reason).'
        '${summary == null || summary.isEmpty ? '' : '\n\n$summary'}';
  }

  Future<void> _storeMessage(String message, String response, bool isDemo) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('chat_history').add({
        'userId': user.uid,
        'userMessage': message,
        'aiResponse': response,
        'preview':
            message.length > 30 ? '${message.substring(0, 27)}...' : message,
        'isDemo': isDemo,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error storing chat message: $e');
    }
  }

  void dispose() {}
}

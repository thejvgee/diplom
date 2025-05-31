import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/gemini_service.dart';

class AIChatbotScreen extends StatefulWidget {
  const AIChatbotScreen({Key? key}) : super(key: key);

  @override
  _AIChatbotScreenState createState() => _AIChatbotScreenState();
}

class _AIChatbotScreenState extends State<AIChatbotScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  late GeminiService _geminiService;
  bool _isLoading = false;
  bool _isError = false;
  bool _isUsingDemoMode = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _showSuggestions = true;
  bool _showHistoryPanel = false;
  List<Map<String, dynamic>> _chatHistoryList = [];
  bool _isLoadingHistory = false;
  StreamSubscription<QuerySnapshot>? _chatSubscription;

  final List<String> _suggestions = [
    "Надад 100'000'000 төгрөг байна, би ямар хөрөнгө оруулалтын багц бүрдүүлэх ёстой вэ?",
    "35 настай хүнд хамгийн оновчтой хөрөнгийн орууалтын багц юу вэ?",
    "Би санхүүгийн баримтлах төсвөө хэрхэн бүрдүүлэх вэ?",
    "22 настай, шинээр ажилд орсон хүн жилдээ 20000000 ₮ орлого олдог тохиолдолд байрны урьдчилгааны хуримтлал үүсгэх хамгийн үр дүнтэй арга юу вэ?",
    "Би 50 настай тэтгэвэрт гарах хүртлээ хэр их мөнгөөр ямар хөрөнгө оруулалтын багц бүрдүүлэх ёстой вэ?",
    "Өнөөгийн зах зээлд криптовалют сайн хөрөнгө оруулалт мөн үү?",
    "Маш бага эрсдэлтэй, жилд дунджаар 10% өгөөжтэй хуримтлалын бүтээгдэхүүн сонгох нь миний зорилтот хугацаанд (5–10 жил) хангалттай юу?",
    "Зах зээлийн уналтын үед би багцаа хэрхэн хамгаалах вэ?",
  ];

  @override
  void initState() {
    super.initState();
    _geminiService = GeminiService();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });
    try {
      final response = await _geminiService.startChat();
      final bool possibleApiKeyIssue = response.contains("problem with the API") || response.contains("backup service");
      setState(() {
        _messages.add({
          'sender': 'Хиймэл оюун зөвлөх',
          'text': "Сайн байна уу! Би Хөрөнгө орууалтын зөвлөх байна.\n Та ямар санхүүгийн зөвөлгөө хүсэж байна вэ!",
          'timestamp': DateTime.now().toString(),
          'isDemo': possibleApiKeyIssue,
        });
        _isLoading = false;
        _isUsingDemoMode = possibleApiKeyIssue;
        _showSuggestions = true;
      });
    } catch (e) {
      setState(() {
        _isError = true;
        _isLoading = false;
        _isUsingDemoMode = true;
        _messages.add({
          'sender': 'Хиймэл оюун зөвлөх',
          'text': "Сайн байна уу! Би Хөрөнгө орууалтын зөвлөх байна. Би одоогоор offline горимд ажиллаж байгаа хэдий ч таньд тусалж чадна гэж бодож байна!",
          'timestamp': DateTime.now().toString(),
          'isDemo': true,
        });
        _showSuggestions = true;
      });
    }
  }

  Future<void> _sendMessage([String? predefinedMessage]) async {
    String message = predefinedMessage ?? _controller.text;
    if (message.isEmpty) return;
    if (predefinedMessage == null) {
      _controller.clear();
    }

    setState(() {
      _messages.add({
        'sender': 'User',
        'text': message,
        'timestamp': DateTime.now().toString(),
      });
      _isLoading = true;
      _isError = false;
      _showSuggestions = false;
    });

    try {
      final response = await _geminiService.sendMessage(message);
      final bool isErrorResponse = response.contains('No internet connection') ||
          response.contains('Unable to connect') ||
          response.contains('Invalid API key') ||
          response.contains('I apologize') ||
          response.contains('trouble accessing') ||
          response.contains('error processing');
      final bool isUsingDemo = response.contains('Please note this is general advice') ||
          response.contains('This is simplified advice') ||
          response.contains('This general advice may need adjustment') ||
          response.contains('This is general guidance');

      setState(() {
        _messages.add({
          'sender': 'Хиймэл оюун зөвлөх',
          'text': response,
          'timestamp': DateTime.now().toString(),
          'isError': isErrorResponse ? true : null,
          'isDemo': isUsingDemo,
        });
        _isError = isErrorResponse;
        _isUsingDemoMode = _isUsingDemoMode || isUsingDemo;
        _isLoading = false;
      });
    } catch (e) {
      _retryCount++;
      setState(() {
        if (_retryCount >= _maxRetries) {
          _isUsingDemoMode = true;
          _messages.add({
            'sender': 'Хиймэл оюун зөвлөх',
            'text': _getSimpleDemoResponse(message),
            'timestamp': DateTime.now().toString(),
            'isDemo': true,
          });
        } else {
          _messages.add({
            'sender': 'Хиймэл оюун зөвлөх',
            'text': "Санхүүгийн мэдээллийн санд холбогдох техникийн түр зуурын асуудал гарлаа.",
            'timestamp': DateTime.now().toString(),
            'isError': true,
          });
          _showSuggestions = true;
        }
        _isError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadChatHistoryList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingHistory = true;
    });

    try {
      _chatSubscription?.cancel();

      _chatSubscription = FirebaseFirestore.instance
          .collection('chat_history')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((querySnapshot) {
        final historyList = querySnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'preview': data['preview'] ?? data['userMessage'],
            'timestamp': (data['timestamp'] as Timestamp).toDate(),
            'isDemo': data['isDemo'] ?? false,
          };
        }).toList();

        setState(() {
          _chatHistoryList = historyList;
          _isLoadingHistory = false;
        });
      });
    } catch (e) {
      print('Error loading chat history: $e');
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _loadChatFromHistory(String messageId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chat_history')
          .doc(messageId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _messages.clear();
          _messages.add({
            'sender': 'User',
            'text': data['userMessage'],
            'timestamp': (data['timestamp'] as Timestamp).toDate().toString(),
          });
          _messages.add({
            'sender': 'Хиймэл оюун зөвлөх',
            'text': data['aiResponse'],
            'timestamp': (data['timestamp'] as Timestamp).toDate().toString(),
            'isDemo': data['isDemo'] ?? false,
          });
          _showHistoryPanel = false;
        });
      }
    } catch (e) {
      print('Error loading chat from history: $e');
    }
  }

  Future<void> _clearAllChatHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingHistory = true;
    });

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('chat_history')
          .where('userId', isEqualTo: user.uid)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      setState(() {
        _chatHistoryList.clear();
        _isLoadingHistory = false;
      });
    } catch (e) {
      print('Error clearing chat history: $e');
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _confirmClearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Чат түүх устгах'),
        content: Text('Та бүх чат түүхийг устгахдаа итгэлтэй байна уу? Энэ үйлдлийг буцаах боломжгүй.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Цуцлах'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Устгах', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearAllChatHistory();
    }
  }

  Future<void> _deleteSingleMessage(String messageId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('chat_history')
          .doc(messageId)
          .delete();
      setState(() {
        _chatHistoryList.removeWhere((item) => item['id'] == messageId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Чат устгагдлаа')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Чат устгах үед алдаа гарлаа: $e')),
      );
      debugPrint('Error deleting message: $e');
    }
  }
  Future<void> _confirmDeleteSingleMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Чат устгах'),
        content: Text('Та энэ чатыг устгахдаа итгэлтэй байна уу?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Цуцлах'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Устгах', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSingleMessage(messageId);
    }
  }

  Future<void> _renameChat(String messageId, String newPreview) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('chat_history')
          .doc(messageId)
          .update({'preview': newPreview});
      setState(() {
        final index = _chatHistoryList
            .indexWhere((item) => item['id'] == messageId);
        if (index != -1) {
          _chatHistoryList[index]['preview'] = newPreview;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Чатыг амжилттай шинэчиллээ')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Чатыг шинэчлэхэд алдаа гарлаа: $e')),
      );
      debugPrint('Error renaming chat: $e');
    }
  }

  Future<void> _confirmRenameChat(
      String messageId, String currentPreview) async {
    final TextEditingController _renameController =
    TextEditingController(text: currentPreview);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Чатын нэр солих'),
        content: TextField(
          controller: _renameController,
          decoration: InputDecoration(
            hintText: 'Шинэ нэрээ оруулна уу',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Цуцлах'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Хадгалах'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newPreview = _renameController.text.trim();
      if (newPreview.isNotEmpty) {
        await _renameChat(messageId, newPreview);
      }
    }
  }
  String _getSimpleDemoResponse(String message) {
    message = message.toLowerCase();
    if (message.contains('хувьцаа') || message.contains('Хөрөнгө оруулалт')) {
      return "Хувьцаанд хөрөнгө оруулахдаа эрсдэлийг бууруулахын тулд хөрөнгө оруулалтаа төрөлжүүлэх нь чухал. Янз бүрийн салбар болон хөрөнгийн ангиллыг (жишээлбэл, ETF) хослуулан эхлээрэй.\n\nАнхлан суралцагчдад индексийн сангууд (index fund) нь зах зээлийг бүхэлд нь хамрах үр дүнтэй арга юм. Олон амжилттай хөрөнгө оруулагчид бага зардалтай, S&P 500 зэрэг гол индексийг дагадаг индексийн санд хөрөнгө оруулж эхлэхийг зөвлөдөг.\n\nБогино хугацаанд хэрэгтэй биш мөнгөө л хөрөнгө оруулалтанд ашиглаарай, учир нь зах зээл хэлбэлзэлтэй байдаг.";
    } else if (message.contains('crypto') || message.contains('bitcoin')) {
      return "Криптовалютын хөрөнгө оруулалт нь ихээхэн хэлбэлзэлтэй тул ихэнх хөрөнгө оруулагчдын хувьд багцынх нь 5%-иас хэтрэхгүй байхаар хязгаарлахыг санхүүгийн зөвлөхүүд санал болгодог.\n\nХэрэв та криптовалют сонирхож байгаа бол шинэ, баталгаажаагүй койнуудаас илүүтэй Биткойн эсвэл Этереум зэрэг тогтсон койнуудаас эхлэх нь зүйтэй.\n\nКриптовалютын зах зээл үнэ ханшийн огцом савлагаа ихтэй тул зөвхөн алдаж болох хэмжээндээ тохируулан хөрөнгө оруулалт хийгээрэй.";
    } else if (message.contains('budget') || message.contains('save')) {
      return "50/30/20 дүрмийг ашиглан хувийн төсөв боловсруулах нь үр дүнтэй байж болно:\n• 50% – хэрэгцээ (орон сууц, хоол, хэрэглээний зардал)\n• 30% – хүсэл (зугаа цэнгэл, гадуур хооллох гэх мэт)\n• 20% – хуримтлал болон өрийн төлбөр\n\nЭхлээд нэг сарын турш зарцуулалтаа хянаж, мөнгө тань юунд зарцуулагдаж байгааг мэдэж аваарай. Үнэгүй апп-ууд энэ процессыг автоматжуулахад тусална.\n\nХуримтлалын хувьд, 3–6 сарын зардлыг бүрдүүлэх яаралтай тусламжийн сан үүсгэсний дараа бусад зорилгод анхаарлаа хандуулаарай.";
    } else if (message.contains('retire') || message.contains('retirement')) {
      return "Тэтгэврийн хуримтлалаа аль болох эрт эхлэх тусам илүү үр ашигтай байдаг — нийлмэл хүүгийн нөлөөгөөр бага мөнгө ч урт хугацаанд өсч чадна.\n\n401(k) зэрэг татварын хөнгөлөлттэй тэтгэврийн хуримтлалын данс ашиглахыг бодолцож үзээрэй, ялангуяа ажил олгогчоос нэмэлт хувь нэмэр оруулдаг бол. Мөн IRA данс ч үр дүнтэй хувилбар юм.\n\nНийт орлогынхоо 15%-ийг тэтгэвэрт зориулан хуримтлуулах нь нийтлэг зөвлөмж боловч таны нас, зорилго, одоогийн хуримтлалаас хамаарч өөр байж болно.";
    } else if (message.contains('debt') || message.contains('loan')) {
      return "Өрийн асуудлыг шийдвэрлэхдээ дараах хоёр аргыг авч үзээрэй:\n\n1. 'Цасны нуранги' арга: Хүү хамгийн өндөртэй өрөөс эхлэн төлөх (математикаар хамгийн үр дүнтэй)\n2. 'Цасан бөмбөлөг' арга: Хамгийн бага үлдэгдэлтэй өрөөс эхлэх (сэтгэлзүйн хувьд сэдэл өгөх)\n\nОюутны зээлийн хувьд, орлоготой уялдуулсан төлбөрийн төлөвлөгөө судлах боломжтой.\n\nЦалингийн зээл эсвэл өндөр хүүтэй кредит картны өрөөс аль болох зайлсхийх хэрэгтэй — эдгээр нь өрийн тойрогт оруулах эрсдэлтэй.";
    } else {
      return "Санхүүгийн суурь зарчмуудын зарим нь:\n\n1. 3–6 сарын зардлыг бүрдүүлэх яаралтай тусламжийн сан үүсгэх\n2. Өндөр хүүтэй өрийг төлөх\n3. Ажил олгогчийн тэтгэврийн нэмэлт хувь нэмрийг ашиглах\n4. Урт хугацааны зорилгод тогтмол хөрөнгө оруулах\n5. Зохих даатгалын хамгаалалттай байх\n\nЭдгээр суурь зарчим нь ихэнх санхүүгийн нөхцөл байдалд хамааралтай бөгөөд санхүүгийн бат бөх үндэс суурийг тавихад тусална.";
    }
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final isUser = message['sender'] == 'User';
    final isError = message['isError'] == true;
    final isDemo = message['isDemo'] == true;
    final text = message['text'] ?? '';
    final bool isInvestmentRecommendation = !isUser &&
        (text.contains('Based on your investment amount') ||
            text.contains('here are the best options'));
    final formattedText = !isUser ? _formatAIResponse(text) : text;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? Colors.red[50]
              : (isUser
              ? Colors.blue[100]
              : (isInvestmentRecommendation
              ? Colors.green[50]
              : (isDemo ? Colors.grey[200] : Colors.blue[50]))),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
          border: isError
              ? Border.all(color: Colors.red.shade200)
              : (isDemo
              ? Border.all(color: Colors.orange.shade200)
              : (isInvestmentRecommendation
              ? Border.all(color: Colors.green.shade300)
              : null)),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && isDemo)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 12, color: Colors.orange),
                    SizedBox(width: 4),
                    Text(
                      'Энгийн зөвөлгөө',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (!isUser && isInvestmentRecommendation)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up, size: 12, color: Colors.green.shade700),
                    SizedBox(width: 4),
                    Text(
                      'Хөрөнгө оруулалтын зөвлөмжүүд',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            isInvestmentRecommendation
                ? _buildInvestmentRecommendationContent(formattedText)
                : Text(
              formattedText,
              style: TextStyle(
                color:
                isError ? Colors.red.shade700 : (isUser ? Colors.black87 : Colors.black),
                height: 1.4,
                fontSize: 15,
              ),
            ),
            if (isError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextButton(
                  onPressed: _initializeChat,
                  child: Text('Чатыг дахин эхлүүлэх'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryPanel() {
    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: MediaQuery.of(context).size.width * 0.7,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: EdgeInsets.only(top: kToolbarHeight),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Чат түүх',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _showHistoryPanel = false;
                      });
                    },
                  ),
                ],
              ),
            ),
            Divider(),
            Expanded(
              child: _isLoadingHistory
                  ? Center(child: CircularProgressIndicator())
                  : _chatHistoryList.isEmpty
                  ? Center(
                child: Text(
                  'Чат түүх хоосон байна',
                  style: TextStyle(color: Colors.grey),
                ),
              )
                  : ListView.builder(
                itemCount: _chatHistoryList.length,
                itemBuilder: (context, index) {
                  final item = _chatHistoryList[index];
                  return ListTile(
                    title: Text(
                      item['preview'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      DateFormat('yyyy-MM-dd HH:mm')
                          .format(item['timestamp']),
                      style: TextStyle(fontSize: 12),
                    ),
                    leading: item['isDemo']
                        ? Icon(Icons.info_outline,
                        size: 16, color: Colors.orange)
                        : null,
                    onTap: () => _loadChatFromHistory(item['id']),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, size: 20),
                          onPressed: () => _confirmRenameChat(
                              item['id'], item['preview']),
                          tooltip: 'Нэр солих',
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 20),
                          onPressed: () =>
                              _confirmDeleteSingleMessage(item['id']),
                          tooltip: 'Устгах',
                          color: Colors.redAccent,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed:
                _chatHistoryList.isEmpty ? null : _confirmClearAllHistory,
                child: Text('Бүгдийг устгах'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.red,
                  minimumSize: Size(double.infinity, 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChips() {
    return Container(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(vertical: 8),
        children: _suggestions.map((suggestion) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ActionChip(
              label: Text(
                suggestion.length > 30
                    ? '${suggestion.substring(0, 27)}...'
                    : suggestion,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue.shade800,
                ),
              ),
              onPressed: () => _sendMessage(suggestion),
              backgroundColor: Colors.blue.shade50,
              elevation: 1,
              shadowColor: Colors.blue.shade100,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.blue.shade200, width: 0.5),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatAIResponse(String text) {
    final bool isInvestmentRecommendation = text.contains('Based on your investment amount') ||text.contains('here are the best options');
    if (isInvestmentRecommendation) {
      return _formatInvestmentRecommendation(text);
    }
    final formattedText = text
        .replaceAllMapped(RegExp(r'^\s*[•-]\s*(.+)$', multiLine: true),
            (match) => '• ${match.group(1)}')
        .replaceAllMapped(RegExp(r'^\s*(\d+)\.\s*(.+)$', multiLine: true),
            (match) => '${match.group(1)}. ${match.group(2)}');
    return formattedText;
  }

  String _formatInvestmentRecommendation(String text) {
    final parts = text.split('\n\n');
    String header = parts.isNotEmpty ? parts[0] : '';
    final formattedText = text.replaceAllMapped(
        RegExp(
            r'^(\d+\.\s+)([A-Z]+(?:\.[A-Z])?):\s+([^-]+)\s*-\s*(.+)$',
            multiLine: true),
            (match) =>
        '${match.group(1)}**${match.group(2)}**: ${match.group(3)} - ${match.group(4)}');
    return formattedText;
  }

  Widget _buildInvestmentRecommendationContent(String text) {
    final lines = text.split('\n');
    String header = '';
    List<String> recommendations = [];
    String footer = '';
    bool inRecommendations = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.contains('here are the best options')) {
        header = line;
        inRecommendations = true;
      } else if (inRecommendations && line.startsWith(RegExp(r'\d+\.'))) {
        recommendations.add(line);
      } else if (inRecommendations && recommendations.isNotEmpty && !line.startsWith(RegExp(r'\d+\.'))) {
        footer = line;
        inRecommendations = false;
      } else if (!inRecommendations && recommendations.isEmpty) {
        header = header.isEmpty ? line : '$header\n$line';
      } else if (!inRecommendations && !recommendations.isEmpty) {
        footer = footer.isEmpty ? line : '$footer\n$line';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          header,
          style: TextStyle(
            color: Colors.black87,
            height: 1.4,
            fontSize: 15,
          ),
        ),
        SizedBox(height: 8),
        ...recommendations.map((rec) {
          final match = RegExp(
              r'^(\d+\.\s+)([A-Z]+(?:\.[A-Z])?):\s+([^-]+)\s*-\s*(.+)$')
              .firstMatch(rec);
          if (match != null) {
            final number = match.group(1) ?? '';
            final symbol = match.group(2) ?? '';
            final name = match.group(3)?.trim() ?? '';
            final reason = match.group(4) ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    number,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                            color: Colors.black87, fontSize: 15, height: 1.4),
                        children: [
                          TextSpan(
                            text: symbol,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                          TextSpan(text: ': '),
                          TextSpan(text: name),
                          TextSpan(text: ' - '),
                          TextSpan(
                            text: reason,
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          } else {
            return Text(rec,
                style: TextStyle(fontSize: 15, height: 1.4));
          }
        }).toList(),
        if (footer.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              footer,
              style: TextStyle(
                color: Colors.black87,
                height: 1.4,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.support_agent, color: Colors.blue.shade700),
              radius: 18,
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI зөвлөх',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Санхүүгийн зөвлөх',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ],
        ),
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.history),
            onPressed: () {
              setState(() {
                _showHistoryPanel = !_showHistoryPanel;
                if (_showHistoryPanel) {
                  _loadChatHistoryList();
                }
              });
            },
            tooltip: 'Чат түүх',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _initializeChat,
            tooltip: 'Чат дахин эхлүүлэх',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_isUsingDemoMode)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade50, Colors.orange.shade100],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.info_outline,
                            size: 14, color: Colors.orange.shade800),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Та энгийн удирдамжийн горимыг ашиглаж байна. Зөвлөх нь шилдэг туршлагад үндэслэн санхүүгийн ерөнхий зөвлөгөө өгнө.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                              height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  reverse: false,
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _isLoading) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return _buildMessage(_messages[index]);
                  },
                ),
              ),
              if (_showSuggestions && _messages.isNotEmpty)
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(),
                      Text(
                        'Try asking about:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: 4),
                      _buildSuggestionChips(),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Өөрийн санхүүгийн талаар асуух асуулт...',
                          prefixIcon:
                          Icon(Icons.account_balance, color: Colors.blue.shade300),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:
                            BorderSide(color: Colors.blue.shade400, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    SizedBox(width: 8),
                    FloatingActionButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      child: _isLoading
                          ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : Icon(Icons.send),
                      mini: true,
                      elevation: 2,
                      backgroundColor:
                      _isLoading ? Colors.grey.shade400 : Colors.blue.shade600,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Зөвөлгөөнүүд нь хиймэл оюун ухаанаар generate хйигдсэн бөгөөд мэргэжлийн санхүүгийн зөвлөгөөг орлохгүй гэдгийг санаарай.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
            ],
          ),
          if (_showHistoryPanel) _buildHistoryPanel(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _chatSubscription?.cancel();
    super.dispose();
  }
}

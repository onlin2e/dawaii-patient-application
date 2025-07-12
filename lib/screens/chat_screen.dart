import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:http/http.dart' as http;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  List<ChatMessage> messages = [];
  final ChatUser currentUser = ChatUser(id: "1", firstName: "User");
  final ChatUser aiUser = ChatUser(
    id: "2",
    firstName: "AI",
    profileImage: "assets/pill-icon-10.jpg",
  );

  @override
  void initState() {
    super.initState();
    messages.add(
      ChatMessage(
        text: "مرحبًا! أنا هنا لمساعدتك والإجابة على استفساراتك. 😊 كيف يمكنني مساعدتك اليوم؟",
        user: aiUser,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _sendMessageToAI(String text) async {
    if (text.trim().isNotEmpty) {
      final userMessage = ChatMessage(
        text: text.trim(),
        user: currentUser,
        createdAt: DateTime.now(),
      );
      
      setState(() {
        messages.insert(0, userMessage);
      });

      // استدعاء دالة OpenAI API
      final aiResponse = await _getAIResponse(text);
      
      if (aiResponse != null) {
        final aiMessage = ChatMessage(
          text: aiResponse,
          user: aiUser,
          createdAt: DateTime.now(),
        );
        setState(() {
          messages.insert(0, aiMessage);
        });
      }
    }
  }
Future<String?> _getAIResponse(String message) async {
  final apiUrl = Uri.parse('https://api.openai.com/v1/chat/completions');
  final apiKey = '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';  // تأكد من أن المفتاح صحيح

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $apiKey',
  };

  final body = jsonEncode({
    'model': 'gpt-3.5-turbo', 
    'messages': [
      {'role': 'system', 'content': 'You are a helpful assistant.'},
      {'role': 'user', 'content': message}
    ],
  });

  try {
    final response = await http.post(apiUrl, headers: headers, body: body);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'];
    } else {
      print('HTTP Error: ${response.statusCode}');
      print('Response Body: ${response.body}'); // طباعة الخطأ بالتفصيل
      return 'حدث خطأ أثناء الاتصال بـ OpenAI. الرجاء المحاولة لاحقًا.';
    }
  } catch (e) {
    print('Exception: $e'); // طباعة الاستثناءات غير المتوقعة
    return 'تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت.';
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DashChat(
        currentUser: currentUser,
        messages: messages,
        onSend: (ChatMessage message) {
          _sendMessageToAI(message.text);
        },
        inputOptions: InputOptions(
          inputDecoration: InputDecoration(
            hintText: "...اكتب رسالتك هنا",
            filled: true,
            fillColor: Colors.grey[200],
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
          ),
          sendButtonBuilder: (void Function() send) => IconButton(
            icon: const Icon(Icons.send, color: Colors.deepPurple),
            onPressed: send,
          ),
        ),
      ),
    );
  }
}

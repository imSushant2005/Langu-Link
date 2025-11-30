import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CallService {
  // REPLACE WITH YOUR PC's IP ADDRESS
  static const String baseUrl = "http://192.168.1.88:8000"; 
  
  Function(String text, String senderId)? onTextReceived;
  
  String? _currentChannelId;
  String? _userId;
  Timer? _pollTimer;
  Set<String> _receivedMessageIds = {};

  Future<void> initialize(String userId) async {
    _userId = userId;
    print("CallService Initialized for user: $userId");
  }

  Future<void> joinChannel(String channelId) async {
    _currentChannelId = channelId;
    _receivedMessageIds.clear();
    _startPolling();
    print("Joined channel (polling): $channelId");
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_currentChannelId == null) return;
      await _fetchMessages();
    });
  }

  Future<void> _fetchMessages() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_messages?channel_id=$_currentChannelId'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> messages = jsonDecode(response.body);
        for (var msg in messages) {
          String msgId = msg['id'];
          String senderId = msg['sender_id'];
          String text = msg['text'];

          // If new message and NOT sent by me
          if (!_receivedMessageIds.contains(msgId)) {
            _receivedMessageIds.add(msgId);
            
            if (senderId != _userId) {
               if (onTextReceived != null) {
                 onTextReceived!(text, senderId);
               }
            }
          }
        }
      }
    } catch (e) {
      print("Polling Error: $e");
    }
  }

  Future<void> sendText(String text) async {
    if (_currentChannelId == null || _userId == null) return;

    try {
      await http.post(
        Uri.parse('$baseUrl/send_message'),
        body: {
          'text': text,
          'sender_id': _userId,
          'channel_id': _currentChannelId,
        },
      );
      print("Sent text: $text");
    } catch (e) {
      print("Send Text Error: $e");
    }
  }

  Future<void> leaveChannel() async {
    _pollTimer?.cancel();
    _currentChannelId = null;
    print("Left channel");
  }

  Future<void> dispose() async {
    await leaveChannel();
  }
}

import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../services/speech_service.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
import '../services/call_service.dart';
import '../services/user_session.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final SpeechService _speechService = SpeechService();
  final TranslationService _translationService = TranslationService();
  final TtsService _ttsService = TtsService();
  final CallService _callService = CallService();

  String _englishText = "Tap microphone to speak";
  String _hindiText = "बोलने के लिए माइक्रोफ़ोन दबाएं";

  bool _isListeningEnglish = false;
  bool _isListeningHindi = false;
  bool _isAutoMode = false;
  bool _isConnected = false;
  String _channelId = "";
  late String _userId; // Store local user ID

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _speechService.initialize();
    await _translationService.initialize();
    await _ttsService.initialize();

    // Use logged-in username
    _userId = UserSession().username;
    await _callService.initialize(_userId);

    _callService.onTextReceived = (text, senderId) async {
      bool isHindi = text.codeUnits.any((c) => c >= 0x0900 && c <= 0x097F);
      String lang = isHindi ? 'hi' : 'en';

      if (mounted) {
        setState(() {
          if (isHindi) {
            _hindiText = text;
          } else {
            _englishText = text;
          }
        });
      }

      // Speak using the SENDER'S voice ID
      await _ttsService.speak(text, lang, userId: senderId);
    };
  }

  @override
  void dispose() {
    _translationService.dispose();
    _speechService.stop();
    _ttsService.stop();
    _callService.dispose();
    super.dispose();
  }

  void _showJoinDialog() {
    final controller = TextEditingController(text: "Room1");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Join Call", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Channel Name",
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Your ID: $_userId",
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _callService.joinChannel(controller.text);
              setState(() {
                _isConnected = true;
                _channelId = controller.text;
              });
            },
            child: const Text("Join"),
          ),
        ],
      ),
    );
  }

  void _toggleAutoMode() {
    setState(() {
      _isAutoMode = !_isAutoMode;
    });
    if (!_isAutoMode) {
      _stopListening();
    } else {
      _handleEnglishSpeech();
      _startAutoModeWatchdog();
    }
  }

  void _handleEnglishSpeech() async {
    if (_isListeningHindi) return;

    setState(() {
      _isListeningEnglish = true;
      _englishText = "Listening...";
    });

    await _speechService.listen(
      localeId: 'en_US',
      onResult: (text) async {
        setState(() => _englishText = text);
        if (text.isNotEmpty) {
          final translation = await _translationService.translate(text, 'en');
          if (mounted) setState(() => _hindiText = translation);
        }
      },
    );

    if (_isAutoMode) {
      _waitForSpeechEndAndProcess('en');
    }
  }

  void _handleHindiSpeech() async {
    if (_isListeningEnglish) return;

    setState(() {
      _isListeningHindi = true;
      _hindiText = "सुन रहा हूँ...";
    });

    await _speechService.listen(
      localeId: 'hi_IN',
      onResult: (text) async {
        setState(() => _hindiText = text);
        if (text.isNotEmpty) {
          final translation = await _translationService.translate(text, 'hi');
          if (mounted) setState(() => _englishText = translation);
        }
      },
    );

    if (_isAutoMode) {
      _waitForSpeechEndAndProcess('hi');
    }
  }

  void _waitForSpeechEndAndProcess(String lang) async {
    String lastText = lang == 'en' ? _englishText : _hindiText;
    int stabilityCount = 0;

    while (_isAutoMode &&
        (lang == 'en' ? _isListeningEnglish : _isListeningHindi)) {
      await Future.delayed(const Duration(milliseconds: 200));
      String currentText = lang == 'en' ? _englishText : _hindiText;

      if (currentText == lastText &&
          currentText != "Listening..." &&
          currentText != "सुन रहा हूँ...") {
        stabilityCount++;
      } else {
        stabilityCount = 0;
        lastText = currentText;
      }

      if (stabilityCount >= 4) {
        _processTurn(lang, currentText);
        break;
      }
    }
  }

  bool _isProcessing = false;

  void _processTurn(String sourceLang, String text) async {
    await _speechService.stop();
    setState(() {
      _isListeningEnglish = false;
      _isListeningHindi = false;
      _isProcessing = true;
    });

    if (text.isEmpty || text == "Listening..." || text == "सुन रहा हूँ...") {
      if (_isAutoMode && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        setState(() => _isProcessing = false);
        if (sourceLang == 'en')
          _handleEnglishSpeech();
        else
          _handleHindiSpeech();
      } else {
        setState(() => _isProcessing = false);
      }
      return;
    }

    String translation;
    if (sourceLang == 'en') {
      translation = await _translationService.translate(text, 'en');
      if (mounted) setState(() => _hindiText = translation);

      // Speak with MY voice ID
      await _ttsService.speak(translation, 'hi', userId: _userId);

      if (_isConnected) await _callService.sendText(translation);

      if (_isAutoMode && mounted) {
        int estimatedDuration = (translation.length * 100) + 1500;
        await Future.delayed(Duration(milliseconds: estimatedDuration));
        setState(() => _isProcessing = false);
        if (mounted && _isAutoMode) _handleHindiSpeech();
      } else {
        setState(() => _isProcessing = false);
      }
    } else {
      translation = await _translationService.translate(text, 'hi');
      if (mounted) setState(() => _englishText = translation);

      // Speak with MY voice ID
      await _ttsService.speak(translation, 'en', userId: _userId);

      if (_isConnected) await _callService.sendText(translation);

      if (_isAutoMode && mounted) {
        int estimatedDuration = (translation.length * 100) + 1500;
        await Future.delayed(Duration(milliseconds: estimatedDuration));
        setState(() => _isProcessing = false);
        if (mounted && _isAutoMode) _handleEnglishSpeech();
      } else {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _startAutoModeWatchdog() {
    Future.doWhile(() async {
      if (!_isAutoMode || !mounted) return false;
      await Future.delayed(const Duration(seconds: 5));
      if (_isAutoMode &&
          !_isListeningEnglish &&
          !_isListeningHindi &&
          !_isProcessing) {
        _handleEnglishSpeech();
      }
      return _isAutoMode;
    });
  }

  void _stopListening() async {
    await _speechService.stop();
    setState(() {
      _isListeningEnglish = false;
      _isListeningHindi = false;
      _isAutoMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Live Conversation"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.call_end : Icons.add_call),
            color: _isConnected ? Colors.redAccent : Colors.white,
            onPressed: () {
              if (_isConnected) {
                _callService.leaveChannel();
                setState(() => _isConnected = false);
              } else {
                _showJoinDialog();
              }
            },
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                _isAutoMode ? "AUTO" : "MANUAL",
                style: TextStyle(
                  color: _isAutoMode ? Colors.greenAccent : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Switch(
            value: _isAutoMode,
            onChanged: (val) => _toggleAutoMode(),
            activeColor: Colors.greenAccent,
            inactiveTrackColor: Colors.grey,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF1E293B),
            onSelected: (value) {
              if (value == 'toggle_voice') {
                setState(() {
                  _ttsService.useClonedVoice = !_ttsService.useClonedVoice;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Cloned Voice: ${_ttsService.useClonedVoice ? 'ON' : 'OFF'}",
                    ),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem(
                  value: 'toggle_voice',
                  child: Row(
                    children: [
                      Icon(
                        _ttsService.useClonedVoice
                            ? Icons.record_voice_over
                            : Icons.voice_over_off,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _ttsService.useClonedVoice
                            ? "Disable Cloned Voice"
                            : "Enable Cloned Voice",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 100), // Spacing for AppBar
            // Hindi Section (Other Person)
            Expanded(
              child: _buildChatBubble(
                text: _hindiText,
                label: "हिंदी (Hindi)",
                isListening: _isListeningHindi,
                color: const Color(0xFFF59E0B), // Amber
                onTap: () {
                  if (!_isAutoMode) {
                    if (_isListeningHindi)
                      _stopListening();
                    else
                      _handleHindiSpeech();
                  }
                },
                alignment: Alignment.centerLeft,
              ),
            ),

            // English Section (You)
            Expanded(
              child: _buildChatBubble(
                text: _englishText,
                label: "English (You)",
                isListening: _isListeningEnglish,
                color: const Color(0xFF6366F1), // Indigo
                onTap: () {
                  if (!_isAutoMode) {
                    if (_isListeningEnglish)
                      _stopListening();
                    else
                      _handleEnglishSpeech();
                  }
                },
                alignment: Alignment.centerRight,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble({
    required String text,
    required String label,
    required bool isListening,
    required Color color,
    required VoidCallback onTap,
    required Alignment alignment,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: alignment == Alignment.centerRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isListening
                    ? color.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: alignment == Alignment.centerRight
                      ? const Radius.circular(20)
                      : Radius.zero,
                  bottomRight: alignment == Alignment.centerLeft
                      ? const Radius.circular(20)
                      : Radius.zero,
                ),
                border: Border.all(
                  color: isListening ? color : Colors.white.withOpacity(0.1),
                  width: isListening ? 2 : 1,
                ),
                boxShadow: isListening
                    ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 15)]
                    : [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isListening)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Listening...",
                          style: TextStyle(color: color, fontSize: 12),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

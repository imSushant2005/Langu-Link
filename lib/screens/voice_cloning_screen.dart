import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:animate_do/animate_do.dart';
import '../services/user_session.dart';

class VoiceCloningScreen extends StatefulWidget {
  const VoiceCloningScreen({super.key});

  @override
  State<VoiceCloningScreen> createState() => _VoiceCloningScreenState();
}

class _VoiceCloningScreenState extends State<VoiceCloningScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // No controller needed, using UserSession
  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isUploading = false;
  String _selectedLang = 'en'; // 'en' or 'hi'

  // REPLACE WITH YOUR PC's IP ADDRESS
  static const String baseUrl = "http://192.168.1.88:8000";

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      // Handle permission denied
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (await _recorder.isRecording()) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });
    } else {
      final dir = await getTemporaryDirectory();
      _recordedFilePath = '${dir.path}/voice_sample_$_selectedLang.wav';

      if (await _recorder.hasPermission()) {
        // High quality recording config
        const config = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        );

        await _recorder.start(config, path: _recordedFilePath!);
        setState(() {
          _isRecording = true;
        });
      }
    }
  }

  Future<void> _uploadSample() async {
    if (_recordedFilePath == null) return;

    // Use session username
    final username = UserSession().username;

    setState(() => _isUploading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/clone'));
      request.files.add(
        await http.MultipartFile.fromPath('file', _recordedFilePath!),
      );
      request.fields['lang'] = _selectedLang;
      request.fields['user_id'] = username;

      var response = await request.send();
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Voice Cloned for $username!",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Upload Failed: ${response.statusCode}"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Voice Setup"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeInDown(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLangOption('en', 'English'),
                        _buildLangOption('hi', 'Hindi'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Display Username (Read-only)
                FadeIn(
                  child: Text(
                    "Cloning for: ${UserSession().username}",
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),

                const SizedBox(height: 30),

                FadeIn(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "Read this aloud:",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedLang == 'en'
                              ? "The quick brown fox jumps over the lazy dog. I am testing my voice clone."
                              : "नमस्ते, मैं अपनी आवाज़ का परीक्षण कर रहा हूँ। यह एक उदाहरण है।",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 50),

                GestureDetector(
                  onTap: _toggleRecording,
                  child: ScaleTransition(
                    scale: _isRecording
                        ? _pulseAnimation
                        : const AlwaysStoppedAnimation(1.0),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isRecording
                              ? [Colors.redAccent, Colors.red]
                              : [
                                  Theme.of(context).primaryColor,
                                  Theme.of(context).colorScheme.secondary,
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_isRecording
                                        ? Colors.red
                                        : Theme.of(context).primaryColor)
                                    .withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isRecording ? "Recording..." : "Tap to Record",
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),

                const SizedBox(height: 40),

                if (_recordedFilePath != null && !_isRecording)
                  FadeInUp(
                    child: SizedBox(
                      width: 200,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isUploading ? null : _uploadSample,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          elevation: 5,
                        ),
                        child: _isUploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.cloud_upload_outlined),
                                  const SizedBox(width: 8),
                                  Text("Save Voice"),
                                ],
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLangOption(String code, String label) {
    final isSelected = _selectedLang == code;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLang = code;
          _recordedFilePath = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

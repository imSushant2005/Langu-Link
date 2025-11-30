import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Completer<void>? _completionCompleter;

  bool useClonedVoice = false;
  // REPLACE WITH YOUR PC's IP ADDRESS
  static const String baseUrl = "http://192.168.1.88:8000";

  Future<void> initialize() async {
    await _flutterTts.setSharedInstance(true);

    if (Platform.isIOS) {
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }

    _flutterTts.setCompletionHandler(() {
      _completionCompleter?.complete();
      _completionCompleter = null;
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      _completionCompleter?.complete();
      _completionCompleter = null;
    });
  }

  Future<void> speak(
    String text,
    String languageCode, {
    String userId = "default",
  }) async {
    if (text.isEmpty) return;

    // Stop any previous speech
    await stop();

    // Create a new completer for this speech
    _completionCompleter = Completer<void>();

    if (useClonedVoice) {
      try {
        print("🗣️ Synthesizing with Cloned Voice for $userId...");

        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/synthesize'),
        );
        request.fields['text'] = text;
        request.fields['language'] = languageCode;
        request.fields['user_id'] = userId; // Use provided user ID

        var response = await request.send();

        if (response.statusCode == 200) {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/tts_output.wav');
          await response.stream.pipe(file.openWrite());

          await _audioPlayer.play(DeviceFileSource(file.path));
          return _completionCompleter?.future;
        } else {
          print(
            "❌ Backend TTS failed: ${response.statusCode}. Falling back to System TTS.",
          );
        }
      } catch (e) {
        print("❌ Backend Connection Error: $e. Falling back to System TTS.");
      }
    }

    // Fallback or Normal System TTS
    String locale = languageCode == 'hi' ? 'hi-IN' : 'en-IN';

    await _flutterTts.setLanguage(locale);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);

    await _flutterTts.speak(text);

    return _completionCompleter?.future;
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    await _audioPlayer.stop();
    if (_completionCompleter != null && !_completionCompleter!.isCompleted) {
      _completionCompleter!.complete();
      _completionCompleter = null;
    }
  }
}

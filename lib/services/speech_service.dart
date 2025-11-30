import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  Future<bool> initialize() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      return false;
    }

    if (!_isInitialized) {
      _isInitialized = await _speech.initialize(
        onError: (val) => print('onError: $val'),
        onStatus: (val) => print('onStatus: $val'),
      );
    }
    return _isInitialized;
  }

  Future<void> listen({
    required Function(String) onResult,
    required String localeId,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isInitialized) {
      _speech.listen(
        onResult: (val) => onResult(val.recognizedWords),
        localeId: localeId,
        listenFor: Duration(seconds: 30),
        pauseFor: Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      );
    }
  }

  Future<void> stop() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}

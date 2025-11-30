import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  final _onDeviceTranslator = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.english,
    targetLanguage: TranslateLanguage.hindi,
  );

  // Cache translators to avoid recreating them
  OnDeviceTranslator? _enToHiTranslator;
  OnDeviceTranslator? _hiToEnTranslator;

  Future<void> initialize() async {
    // Pre-download models if needed
    final modelManager = OnDeviceTranslatorModelManager();
    await modelManager.downloadModel(TranslateLanguage.english.bcpCode);
    await modelManager.downloadModel(TranslateLanguage.hindi.bcpCode);
  }

  Future<String> translate(String text, String sourceLang) async {
    if (text.isEmpty) return '';

    try {
      if (sourceLang == 'en') {
        _enToHiTranslator ??= OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.english,
          targetLanguage: TranslateLanguage.hindi,
        );
        return await _enToHiTranslator!.translateText(text);
      } else {
        _hiToEnTranslator ??= OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.hindi,
          targetLanguage: TranslateLanguage.english,
        );
        return await _hiToEnTranslator!.translateText(text);
      }
    } catch (e) {
      print('Translation Error: $e');
      return text; // Return original text on failure
    }
  }

  void dispose() {
    _enToHiTranslator?.close();
    _hiToEnTranslator?.close();
  }
}

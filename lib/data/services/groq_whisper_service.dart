// ==============================================================================
// Groq Whisper Transcription Service
// File: lib/data/services/groq_whisper_service.dart
//
// Converts recorded or imported audio into timestamped segments (FR3).
// Uses Groq-hosted Whisper-large-v3 with code-switching prompt.
// ==============================================================================

import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';
import '../models/qayd_model.dart';

/// The result returned after successful transcription
class TranscriptionResult {
  final String text;
  final List<TranscriptSegment> segments;
  final QaydLanguage language;
  final double durationSec;

  const TranscriptionResult({
    required this.text,
    required this.segments,
    required this.language,
    required this.durationSec,
  });
}

class GroqWhisperService {
  final Dio _dio;
  final String _apiKey;

  GroqWhisperService({
    Dio? dio,
    String? apiKey,
  })  : _dio = dio ?? Dio(),
        _apiKey = apiKey ?? ApiConstants.groqApiKey;

  /// Transcribes the given audio file using Groq Whisper-large-v3.
  /// If [audioLanguage] is null or 'auto', Groq Whisper automatically detects
  /// the spoken language (FR3 verbatim transcription without translation).
  Future<TranscriptionResult> transcribeAudio({
    required String audioFilePath,
    String? customApiKey,
    String? audioLanguage,
    ProgressCallback? onSendProgress,
  }) async {
    final result = await _transcribeFile(
      audioFilePath: audioFilePath,
      customApiKey: customApiKey,
      audioLanguage: audioLanguage,
      onSendProgress: onSendProgress,
    );

    if (result.text.trim().isEmpty && result.segments.isEmpty) {
      throw Exception(
        'No clear speech could be transcribed from this audio. Please try recording closer to the microphone or in a quieter environment.',
      );
    }
    return result;
  }

  /// Transcribes a long recording split into [chunkPaths], then merges the
  /// results with offset timestamps. Silent chunks are skipped (not fatal).
  Future<TranscriptionResult> transcribeAudioChunked({
    required List<String> chunkPaths,
    int chunkDurationSec = 600,
    String? customApiKey,
    String? audioLanguage,
    void Function(int completed, int total)? onChunkProgress,
  }) async {
    if (chunkPaths.isEmpty) {
      throw Exception('No audio chunks to transcribe.');
    }

    final results = <TranscriptionResult>[];
    final offsets = <double>[];
    final total = chunkPaths.length;

    for (var i = 0; i < total; i++) {
      onChunkProgress?.call(i, total);
      final result = await _transcribeFile(
        audioFilePath: chunkPaths[i],
        customApiKey: customApiKey,
        audioLanguage: audioLanguage,
      );
      if (result.text.trim().isNotEmpty || result.segments.isNotEmpty) {
        results.add(result);
        offsets.add((i * chunkDurationSec).toDouble());
      }
    }
    onChunkProgress?.call(total, total);

    if (results.isEmpty) {
      throw Exception(
        'No clear speech could be transcribed from this audio. Please try recording closer to the microphone or in a quieter environment.',
      );
    }

    return mergeChunkResults(results, chunkOffsetsSec: offsets);
  }

  /// Pure merge of per-chunk transcription results. Each chunk's segments are
  /// shifted by its offset so timestamps stay contiguous across the lecture.
  static TranscriptionResult mergeChunkResults(
    List<TranscriptionResult> results, {
    List<double>? chunkOffsetsSec,
    double defaultChunkOffsetSec = 600.0,
  }) {
    final allSegments = <TranscriptSegment>[];
    final textParts = <String>[];
    var maxEnd = 0.0;

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      final offset = (chunkOffsetsSec != null && i < chunkOffsetsSec.length)
          ? chunkOffsetsSec[i]
          : i * defaultChunkOffsetSec;

      for (final segment in result.segments) {
        allSegments.add(
          TranscriptSegment(
            startSec: segment.startSec + offset,
            endSec: segment.endSec + offset,
            text: segment.text,
          ),
        );
      }

      final text = result.text.trim();
      if (text.isNotEmpty) {
        textParts.add(text);
      }

      final chunkEnd = offset + result.durationSec;
      if (chunkEnd > maxEnd) maxEnd = chunkEnd;
    }

    final fullText = textParts.join(' ');
    return TranscriptionResult(
      text: fullText,
      segments: allSegments,
      language: _detectLanguage(fullText, null),
      durationSec: maxEnd,
    );
  }

  /// Performs a single Groq Whisper request without the single-file
  /// empty-speech guard, so chunked transcription can skip silent chunks.
  Future<TranscriptionResult> _transcribeFile({
    required String audioFilePath,
    String? customApiKey,
    String? audioLanguage,
    ProgressCallback? onSendProgress,
  }) async {
    final key = customApiKey ?? _apiKey;
    if (key.trim().isEmpty) {
      throw Exception(
        'Groq API key is missing. Please provide it in ApiConstants or via --dart-define=GROQ_API_KEY.',
      );
    }

    final file = File(audioFilePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found at: $audioFilePath');
    }

    // Build the multipart request payload matching Groq Whisper API specs
    final fileName = audioFilePath.split(RegExp(r'[/\\]')).last;
    final map = <String, dynamic>{
      'file': await MultipartFile.fromFile(
        audioFilePath,
        filename: fileName,
      ),
      'model': ApiConstants.groqModel,
      'response_format': 'verbose_json',
      'temperature': '0.0',
      'timestamp_granularities[]': 'segment',
      'prompt': ApiConstants.groqPrompt,
    };

    // Auto-detection by default: only supply language if explicitly specified.
    if (audioLanguage != null &&
        audioLanguage.isNotEmpty &&
        audioLanguage != 'auto') {
      map['language'] = audioLanguage;
    }

    final formData = FormData.fromMap(map);

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.groqBaseUrl,
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
          },
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onSendProgress: onSendProgress,
      );

      final data = response.data;
      if (data == null) {
        throw Exception('Received empty response from Groq API');
      }

      return parseTranscriptionResponse(data);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final data = e.response?.data;
      String? errorMsg;
      if (data is Map && data['error'] is Map) {
        errorMsg = data['error']['message']?.toString();
      }
      errorMsg ??= e.message;

      if (statusCode == 401) {
        throw Exception('Invalid Groq API key (401 Unauthorized).');
      } else if (statusCode == 413) {
        throw Exception(
          'Compressed audio exceeds Groq upload limit (25 MB on Free Tier, 100 MB on Developer Tier).',
        );
      } else if (statusCode == 429) {
        throw Exception('Groq API rate limit exceeded. Please wait a moment.');
      } else {
        throw Exception('Transcription failed ($statusCode): $errorMsg');
      }
    }
  }

  /// Parses raw JSON response from Groq into a typed TranscriptionResult
  static TranscriptionResult parseTranscriptionResponse(
      Map<String, dynamic> data) {
    final rawFullText = (data['text'] as String? ?? '').trim();
    final duration = (data['duration'] as num?)?.toDouble() ?? 0.0;

    // Parse timestamped segments (FR8 support), filtering Whisper silence hallucinations
    // and prompt echoes so they never pollute transcripts or downstream summaries.
    final segmentsList = <TranscriptSegment>[];
    var droppedHallucination = false;

    if (data['segments'] is List) {
      for (final item in data['segments'] as List) {
        if (item is Map) {
          final start = (item['start'] as num?)?.toDouble() ?? 0.0;
          final end = (item['end'] as num?)?.toDouble() ?? 0.0;
          final segText = (item['text'] as String? ?? '').trim();
          final noSpeechProb = (item['no_speech_prob'] as num?)?.toDouble();
          final avgLogprob = (item['avg_logprob'] as num?)?.toDouble();
          final compressionRatio =
              (item['compression_ratio'] as num?)?.toDouble();

          if (segText.isEmpty) continue;

          if (_isHallucinatedSegment(
            segText,
            noSpeechProb: noSpeechProb,
            avgLogprob: avgLogprob,
            compressionRatio: compressionRatio,
          )) {
            droppedHallucination = true;
            continue;
          }

          // Whisper silence/loop repetition detection: drop consecutive duplicate text
          if (segmentsList.isNotEmpty &&
              segmentsList.last.text.trim().toLowerCase() ==
                  segText.toLowerCase()) {
            droppedHallucination = true;
            continue;
          }

          segmentsList.add(
            TranscriptSegment(
              startSec: start,
              endSec: end,
              text: segText,
            ),
          );
        }
      }
    }

    final fullText = droppedHallucination
        ? segmentsList.map((s) => s.text).join(' ').trim()
        : (rawFullText.isNotEmpty || segmentsList.isEmpty
            ? rawFullText
            : segmentsList.map((s) => s.text).join(' ').trim());

    // Guard top-level text when Groq omits segment-level breakdown.
    final cleanFullText =
        (!droppedHallucination && _isKnownHallucinationText(fullText))
            ? ''
            : fullText;

    // Detect language: check for mixed script (Arabic + Latin)
    final language = _detectLanguage(cleanFullText, data['language'] as String?);

    return TranscriptionResult(
      text: cleanFullText,
      segments: segmentsList,
      language: language,
      durationSec: duration,
    );
  }

  static const Set<String> _phantomCredits = {
    'ترجمه نانسي قنقر',
    'نانسي قنقر',
    'الترجمه نانسي قنقر',
    'ترجمه نانسي',
    'اشتركوا في القناه',
    'اشترك في القناه',
    'لا تنسوا الاشتراك في القناه',
    'لا تنس الاشتراك في القناه',
    'شكرا للمشاهده',
    'شكرا على المشاهده',
    'شكرا لحسن استماعكم',
    'thank you for watching',
    'thanks for watching',
    'please subscribe',
    'subscribe to the channel',
    'subtitles by amara org',
    'amara org',
  };

  static bool _isHallucinatedSegment(
    String text, {
    double? noSpeechProb,
    double? avgLogprob,
    double? compressionRatio,
  }) {
    // Standard Whisper silent/loop suppression thresholds when Groq includes metadata.
    if (noSpeechProb != null &&
        noSpeechProb > 0.6 &&
        (avgLogprob == null || avgLogprob < -1.0)) {
      return true;
    }
    if (compressionRatio != null &&
        compressionRatio > 2.4 &&
        (avgLogprob == null || avgLogprob < -1.0)) {
      return true;
    }

    return _isKnownHallucinationText(text);
  }

  static bool _isKnownHallucinationText(String text) {
    final normalized = _normalizeForHallucinationCheck(text);
    if (normalized.isEmpty) return true;

    if (_phantomCredits.contains(normalized)) {
      return true;
    }
    if (normalized.contains('نانسي قنقر') &&
        normalized.split(' ').length <= 5) {
      return true;
    }

    final normalizedPrompt =
        _normalizeForHallucinationCheck(ApiConstants.groqPrompt);
    final normalizedArabicPrompt =
        _normalizeForHallucinationCheck(ApiConstants.groqArabicPrompt);
    final normalizedEnglishPrompt =
        _normalizeForHallucinationCheck(ApiConstants.groqEnglishPrompt);

    if (normalized == normalizedPrompt ||
        normalized == normalizedArabicPrompt ||
        normalized == normalizedEnglishPrompt ||
        normalized.contains('transcribe arabic speech') ||
        normalized.contains('tanscribe arabic speech') ||
        normalized.contains('maintain strict code switching') ||
        normalized.contains('transcribe verbatim') ||
        normalized.contains('programming concepts and following egp') ||
        normalized == 'what is the difference between arabic and english' ||
        normalized.startsWith('api database backend frontend')) {
      return true;
    }

    return false;
  }

  static String _normalizeForHallucinationCheck(String input) {
    var s = input.toLowerCase();
    // Strip Arabic diacritics (tashkeel) and tatweel
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
    // Normalize common Arabic orthographic variants
    s = s
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
    // Strip punctuation and collapse whitespace
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Checks script diversity to detect Arabic, English, or Code-Switched (Mixed)
  static QaydLanguage _detectLanguage(String text, String? reportedLanguage) {
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    final hasLatin = RegExp(r'[a-zA-Z]').hasMatch(text);

    if (hasArabic && hasLatin) {
      return QaydLanguage.mixed;
    } else if (hasArabic) {
      return QaydLanguage.ar;
    } else if (hasLatin) {
      return QaydLanguage.en;
    }

    if (reportedLanguage?.toLowerCase() == 'arabic') return QaydLanguage.ar;
    if (reportedLanguage?.toLowerCase() == 'english') return QaydLanguage.en;
    return QaydLanguage.mixed;
  }
}

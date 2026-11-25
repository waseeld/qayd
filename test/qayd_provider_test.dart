// ==============================================================================
// Qayd Provider Unit Tests
// File: test/qayd_provider_test.dart
// ==============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/models/folder_model.dart';
import 'package:qayd/data/models/qayd_model.dart';
import 'package:qayd/data/services/audio_compression_service.dart';
import 'package:qayd/data/services/audio_picker_service.dart';
import 'package:qayd/data/services/audio_recording_service.dart';
import 'package:qayd/data/services/gemini_summary_service.dart';
import 'package:qayd/data/services/groq_whisper_service.dart';
import 'package:qayd/data/services/storage_service.dart';
import 'package:qayd/providers/qayd_provider.dart';

class MockStorageService extends StorageService {
  final List<Qayd> _qayds = [];
  final List<QaydFolder> _folders = [];
  bool _seeded = false;

  @override
  bool get hasSeededDemo => _seeded;

  @override
  Future<void> markDemoSeeded() async {
    _seeded = true;
  }

  @override
  Qayd? getQayd(String id) {
    for (final q in _qayds) {
      if (q.id == id) return q;
    }
    return null;
  }

  @override
  List<Qayd> getAllQayds() => List.unmodifiable(_qayds);

  @override
  List<Qayd> getQaydsByFolder(String? folderId) {
    return _qayds.where((q) => q.folderId == folderId).toList();
  }

  @override
  List<QaydFolder> getAllFolders() => List.unmodifiable(_folders);

  @override
  Future<void> saveQayd(Qayd qayd) async {
    _qayds.removeWhere((q) => q.id == qayd.id);
    _qayds.add(qayd);
  }

  @override
  Future<void> deleteQayd(String id) async {
    _qayds.removeWhere((q) => q.id == id);
  }

  @override
  Future<void> saveFolder(QaydFolder folder) async {
    _folders.removeWhere((f) => f.id == folder.id);
    _folders.add(folder);
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    for (final qayd in getQaydsByFolder(folderId)) {
      await saveQayd(qayd.copyWith(clearFolderId: true));
    }
    _folders.removeWhere((f) => f.id == folderId);
  }
}

class FakeFailingStopRecordingService extends AudioRecordingService {
  @override
  Future<String?> stopRecording() async => null;
}

class FakeSuccessWhisperService extends GroqWhisperService {
  @override
  Future<TranscriptionResult> transcribeAudio({
    required String audioFilePath,
    String? customApiKey,
    String? audioLanguage = 'ar',
    void Function(int count, int total)? onSendProgress,
  }) async {
    return const TranscriptionResult(
      text: 'Test lecture about REST APIs.',
      durationSec: 60.0,
      language: QaydLanguage.en,
      segments: [
        TranscriptSegment(
          startSec: 0.0,
          endSec: 15.0,
          text: 'Test lecture about REST APIs.',
        ),
      ],
    );
  }
}

class FakeValidRecordingService extends AudioRecordingService {
  @override
  Future<String?> stopRecording() async => '/tmp/mock_recording.m4a';
}

class FakeFlakyGeminiService extends GeminiSummaryService {
  bool shouldFail = true;
  List<TranscriptSegment> lastReceivedSegments = const [];
  String lastReceivedLanguage = 'en';

  @override
  Future<QaydSummary> generateSummary({
    required String transcript,
    List<TranscriptSegment> segments = const [],
    String summaryLanguage = 'en',
    String? customApiKey,
  }) async {
    lastReceivedSegments = segments;
    lastReceivedLanguage = summaryLanguage;
    if (shouldFail) {
      throw Exception('Simulated Gemini 429');
    }
    return const QaydSummary(
      overview: 'Recovered summary.',
      sections: [
        SummarySection(
          heading: 'REST APIs',
          startSec: 0.0,
          summary: 'Introduces REST principles.',
        ),
      ],
      keyPoints: ['Stateless communication'],
      keyTerms: [KeyTerm(term: 'REST', definition: 'Representational State Transfer')],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QaydProvider Unit Tests', () {
    late MockStorageService mockStorage;
    late QaydProvider provider;

    setUp(() {
      mockStorage = MockStorageService();
      provider = QaydProvider(
        storageService: mockStorage,
        whisperService: GroqWhisperService(),
        summaryService: GeminiSummaryService(),
        recordingService: AudioRecordingService(),
        pickerService: AudioPickerService(),
      );
    });

    test('Locale and Theme toggling works correctly (FR7)', () {
      expect(provider.currentLocale.languageCode, 'en');
      provider.toggleLocale();
      expect(provider.currentLocale.languageCode, 'ar');
      provider.toggleLocale();
      expect(provider.currentLocale.languageCode, 'en');

      expect(provider.isDarkMode, false);
      provider.toggleTheme();
      expect(provider.isDarkMode, true);
      provider.toggleTheme();
      expect(provider.isDarkMode, false);
    });

    test('saveApiKeys stores and clears both API keys', () async {
      await provider.saveApiKeys(
        groqApiKey: '  gsk_test_key  ',
        geminiApiKey: ' AIza_test_key ',
      );
      expect(provider.groqApiKey, 'gsk_test_key');
      expect(provider.geminiApiKey, 'AIza_test_key');

      await provider.saveApiKeys(groqApiKey: '', geminiApiKey: '');
      expect(provider.groqApiKey, '');
      expect(provider.geminiApiKey, '');
    });

    test('Loads and seeds demo data when storage is empty', () async {
      provider.loadInitialData();
      // Allow async seeding to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.folders.isNotEmpty, true);
      expect(provider.folders.first.name, 'Operating Systems');

      expect(provider.qayds.isNotEmpty, true);
      expect(provider.qayds.first.title, contains('CS341'));
      expect(provider.qayds.first.summary, isNotNull);
      expect(provider.qayds.first.segments.length, 5);
    });

    test('Filters Qayds by search query correctly', () async {
      provider.loadInitialData();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      provider.setSearchQuery('threads');
      expect(provider.qayds.length, 1);

      provider.setSearchQuery('non_existent_query_xyz');
      expect(provider.qayds.isEmpty, true);

      provider.setSearchQuery('');
      expect(provider.qayds.isNotEmpty, true);
    });

    test('Unfiles Qayds on moveQaydToFolder(null) and deleteFolder', () async {
      provider.loadInitialData();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final demoQayd = provider.qayds.first;
      final folderId = provider.folders.first.id;
      expect(demoQayd.folderId, folderId);

      // Unfile directly back to Root
      await provider.moveQaydToFolder(demoQayd.id, null);
      expect(provider.qayds.first.folderId, isNull);

      // Re-assign to folder, then delete folder -> should unfile back to Root
      await provider.moveQaydToFolder(demoQayd.id, folderId);
      expect(provider.qayds.first.folderId, folderId);

      await provider.deleteFolder(folderId);
      expect(provider.folders, isEmpty);
      expect(provider.qayds.first.folderId, isNull);
    });

    test('editTranscriptSegment preserves timestamps and rebuilds transcript', () async {
      provider.loadInitialData();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final qayd = provider.qayds.first;
      provider.setActiveQayd(qayd);

      await provider.editTranscriptSegment(qayd.id, 0, 'Corrected opening.');
      final updated = provider.qayds.first;

      expect(updated.segments.length, 5);
      expect(updated.segments[0].startSec, 0.0);
      expect(updated.segments[0].text, 'Corrected opening.');
      expect(updated.transcript, startsWith('Corrected opening. '));
      expect(provider.activeQayd?.segments[0].text, 'Corrected opening.');
    });

    test('renameQayd keeps activeQayd in sync', () async {
      provider.loadInitialData();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final qayd = provider.qayds.first;
      provider.setActiveQayd(qayd);

      await provider.renameQayd(qayd.id, 'CS341: Concurrency');
      expect(provider.qayds.first.title, 'CS341: Concurrency');
      expect(provider.activeQayd?.title, 'CS341: Concurrency');
    });

    test('AudioCompressionService size gate enforces strictly < 100 MB', () {
      const hundredMb = 100 * 1024 * 1024;
      expect(AudioCompressionService.isSizeTranscribable(0), false);
      expect(AudioCompressionService.isSizeTranscribable(hundredMb - 1), true);
      expect(AudioCompressionService.isSizeTranscribable(hundredMb), false);
    });

    test('stopRecordingAndProcess sets errorMessage and avoids spinner deadlock',
        () async {
      final failingProvider = QaydProvider(
        storageService: mockStorage,
        whisperService: GroqWhisperService(),
        summaryService: GeminiSummaryService(),
        recordingService: FakeFailingStopRecordingService(),
        pickerService: AudioPickerService(),
      );

      await expectLater(
        () => failingProvider.stopRecordingAndProcess(),
        throwsException,
      );

      expect(failingProvider.isRecording, false);
      expect(failingProvider.isPaused, false);
      expect(failingProvider.errorMessage, contains('no valid audio file'));
    });

    test('Gemini failure scopes errorQaydId, keeps progress < 1.0, and retrySummary recovers',
        () async {
      final whisper = FakeSuccessWhisperService();
      final gemini = FakeFlakyGeminiService();
      final pipelineProvider = QaydProvider(
        storageService: mockStorage,
        whisperService: whisper,
        summaryService: gemini,
        recordingService: FakeValidRecordingService(),
        pickerService: AudioPickerService(),
      );

      final failedQayd = await pipelineProvider.stopRecordingAndProcess(
        title: 'API Lecture',
      );

      expect(failedQayd.status, QaydStatus.failed);
      expect(failedQayd.transcript, 'Test lecture about REST APIs.');
      expect(gemini.lastReceivedSegments.length, 1);
      expect(pipelineProvider.processingProgress, 0.65);
      expect(pipelineProvider.errorMessage, contains('Simulated Gemini 429'));
      expect(pipelineProvider.errorQaydId, failedQayd.id);

      // Now retry and verify recovery + sections + progress = 1.0
      gemini.shouldFail = false;
      await pipelineProvider.retrySummary(failedQayd.id);

      expect(pipelineProvider.errorMessage, isNull);
      expect(pipelineProvider.errorQaydId, isNull);
      expect(pipelineProvider.processingProgress, 1.0);
      expect(pipelineProvider.activeQayd?.status, QaydStatus.done);
      expect(pipelineProvider.activeQayd?.summary?.sections.length, 1);
    });

    test('renameFolder updates folder name and last-item delete does not re-seed demo',
        () async {
      provider.loadInitialData();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final demoFolder = provider.folders.first;
      final demoQayd = provider.qayds.first;

      await provider.renameFolder(demoFolder.id, 'Systems Programming');
      expect(provider.folders.first.name, 'Systems Programming');

      await provider.deleteQayd(demoQayd.id);
      await provider.deleteFolder(demoFolder.id);

      expect(provider.qayds, isEmpty);
      expect(provider.folders, isEmpty);

      // Reloading after user deletes all items must remain empty
      provider.loadInitialData();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.qayds, isEmpty);
      expect(provider.folders, isEmpty);
    });
  });
}

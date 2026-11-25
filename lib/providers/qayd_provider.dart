// ==============================================================================
// Qayd State Provider (ChangeNotifier)
// File: lib/providers/qayd_provider.dart
//
// The central controller that manages state across all screens:
// - Manages the list of saved Qayds and folders (FR6, NFR10).
// - Orchestrates the pipeline: Record/Import -> Transcribe -> Summarize -> Save (FR1-FR4).
// - Ensures the critical reliability invariant: Transcript is persisted before
//   requesting summary so work is never lost on summary failure (NFR3).
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/models/qayd_model.dart';
import '../data/models/folder_model.dart';
import '../data/services/storage_service.dart';
import '../data/services/groq_whisper_service.dart';
import '../data/services/gemini_summary_service.dart';
import '../data/services/audio_recording_service.dart';
import '../data/services/audio_picker_service.dart';
import '../data/services/audio_compression_service.dart';
import '../data/services/audio_splitter_service.dart';

class QaydProvider extends ChangeNotifier {
  final StorageService storageService;
  final GroqWhisperService whisperService;
  final GeminiSummaryService summaryService;
  final AudioRecordingService recordingService;
  final AudioPickerService pickerService;
  final AudioCompressionService compressionService;
  final AudioSplitterService splitterService;

  // --- State Variables ---
  List<Qayd> _qayds = [];
  List<QaydFolder> _folders = [];
  String? _selectedFolderId;
  String _searchQuery = '';

  // Currently active or processing Qayd
  Qayd? _activeQayd;
  String _processingStatusMessage = '';
  double _processingProgress = 0.0;
  String? _errorMessage;
  String? _errorQaydId;
  bool _isRetryingSummary = false;

  // Recording State
  bool _isRecording = false;
  bool _isPaused = false;
  int _recordDurationSeconds = 0;

  // Photos captured during the active recording (linked to elapsed time)
  List<LecturePhoto> _pendingPhotos = [];

  // User-configured API keys (persisted once via Settings)
  String? _groqApiKey;
  String? _geminiApiKey;

  // Language & Theme State (FR7)
  Locale _currentLocale = const Locale('en');
  ThemeMode _themeMode = ThemeMode.system;
  bool _hasSeededSession = false;

  QaydProvider({
    required this.storageService,
    required this.whisperService,
    required this.summaryService,
    required this.recordingService,
    required this.pickerService,
    AudioCompressionService? compressionService,
    AudioSplitterService? splitterService,
  })  : compressionService = compressionService ?? AudioCompressionService(),
        splitterService = splitterService ?? AudioSplitterService() {
    // Listen to recording timer stream
    recordingService.durationStream.listen((seconds) {
      _recordDurationSeconds = seconds;
      notifyListeners();
    });
  }

  // --- Getters ---
  List<Qayd> get qayds {
    var list = _qayds;
    if (_selectedFolderId != null) {
      list = list.where((q) => q.folderId == _selectedFolderId).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((item) {
        return item.title.toLowerCase().contains(q) ||
            item.transcript.toLowerCase().contains(q) ||
            (item.summary?.overview.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    return list;
  }

  List<QaydFolder> get folders => _folders;
  String? get selectedFolderId => _selectedFolderId;
  String get searchQuery => _searchQuery;

  Qayd? get activeQayd => _activeQayd;
  String get processingStatusMessage => _processingStatusMessage;
  double get processingProgress => _processingProgress;
  String? get errorMessage => _errorMessage;
  String? get errorQaydId => _errorQaydId;
  bool get isRetryingSummary => _isRetryingSummary;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  int get recordDurationSeconds => _recordDurationSeconds;

  List<LecturePhoto> get pendingPhotos => _pendingPhotos;

  /// Appends photos captured in a camera session to the active recording.
  void addPendingPhotos(List<LecturePhoto> photos) {
    if (photos.isEmpty) return;
    _pendingPhotos = [..._pendingPhotos, ...photos];
    notifyListeners();
  }

  /// Clears the pending photo buffer (e.g. when a new recording starts).
  void clearPendingPhotos() {
    if (_pendingPhotos.isEmpty) return;
    _pendingPhotos = [];
    notifyListeners();
  }

  /// The saved Groq API key ('' when none set).
  String get groqApiKey => _groqApiKey ?? '';

  /// The saved Gemini API key ('' when none set).
  String get geminiApiKey => _geminiApiKey ?? '';

  /// Effective key to send to Groq: the user-saved key when present, otherwise
  /// null so the service falls back to its compile-time (--dart-define) default.
  String? get _effectiveGroqApiKey {
    final key = _groqApiKey?.trim();
    return (key != null && key.isNotEmpty) ? key : null;
  }

  /// Effective key to send to Gemini: user-saved key when present, else null.
  String? get _effectiveGeminiApiKey {
    final key = _geminiApiKey?.trim();
    return (key != null && key.isNotEmpty) ? key : null;
  }

  Locale get currentLocale => _currentLocale;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void setLocale(Locale locale) {
    if (_currentLocale != locale) {
      _currentLocale = locale;
      notifyListeners();
    }
  }

  void toggleLocale() {
    _currentLocale = _currentLocale.languageCode == 'ar'
        ? const Locale('en')
        : const Locale('ar');
    notifyListeners();
  }

  void toggleTheme() {
    if (_themeMode == ThemeMode.dark) {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.dark;
    }
    notifyListeners();
  }

  /// Persists the user's API keys once so they never have to re-enter them.
  /// Empty values clear the corresponding key.
  Future<void> saveApiKeys({
    required String groqApiKey,
    required String geminiApiKey,
  }) async {
    _groqApiKey = groqApiKey.trim();
    _geminiApiKey = geminiApiKey.trim();
    await storageService.saveApiKeys(
      groqApiKey: _groqApiKey!,
      geminiApiKey: _geminiApiKey!,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Initialization & Loading (FR6)
  // ---------------------------------------------------------------------------

  /// Loads saved Qayds, folders and user API keys from local storage
  void loadInitialData() {
    _groqApiKey = storageService.groqApiKey;
    _geminiApiKey = storageService.geminiApiKey;
    _qayds = storageService.getAllQayds();
    _folders = storageService.getAllFolders();

    // If storage is empty, seed a sample lecture note only once per install so
    // deleting the last user Qayd & folder never resurrects demo data.
    if (_qayds.isEmpty && _folders.isEmpty) {
      if (!storageService.hasSeededDemo && !_hasSeededSession) {
        _seedDemoData();
      } else {
        notifyListeners();
      }
    } else {
      _hasSeededSession = true;
      if (!storageService.hasSeededDemo) {
        storageService.markDemoSeeded();
      }
      notifyListeners();
    }
  }

  Future<void> _seedDemoData() async {
    _hasSeededSession = true;
    await storageService.markDemoSeeded();
    final folderId = const Uuid().v4();
    final demoFolder = QaydFolder(
      id: folderId,
      name: 'Operating Systems',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    await storageService.saveFolder(demoFolder);

    final demoQayd = Qayd(
      id: const Uuid().v4(),
      title: 'CS341: Processes vs Threads',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      audioPath: '',
      durationSec: 125,
      language: QaydLanguage.mixed,
      status: QaydStatus.done,
      folderId: folderId,
      transcript:
          'السلام عليكم جميعاً. Today we will cover the fundamental distinction between a Process and a Thread in modern operating systems. First, what is a Process? A process is an executing program with its own dedicated memory address space, including its code section, data section, heap, and stack. Because processes are isolated by the OS kernel, inter-process communication requires IPC mechanisms like pipes, message queues, or shared memory. In contrast, a Thread is often called a lightweight process (LWP). Threads belonging to the same process share the same code and heap, but each thread possesses its own program counter and stack. This makes thread switching much faster than full process context switching. However, because threads share memory, developers must use synchronization primitives like mutexes and semaphores to prevent race conditions and data corruption. Next lecture, we will dive deeper into CPU scheduling algorithms.',
      segments: const [
        TranscriptSegment(
          startSec: 0.0,
          endSec: 15.0,
          text:
              'السلام عليكم جميعاً. Today we will cover the fundamental distinction between a Process and a Thread in modern operating systems.',
        ),
        TranscriptSegment(
          startSec: 15.0,
          endSec: 45.0,
          text:
              'First, what is a Process? A process is an executing program with its own dedicated memory address space, including its code section, data section, heap, and stack.',
        ),
        TranscriptSegment(
          startSec: 45.0,
          endSec: 75.0,
          text:
              'Because processes are isolated by the OS kernel, inter-process communication requires IPC mechanisms like pipes, message queues, or shared memory.',
        ),
        TranscriptSegment(
          startSec: 75.0,
          endSec: 100.0,
          text:
              'In contrast, a Thread is often called a lightweight process (LWP). Threads belonging to the same process share the same code and heap, but each thread possesses its own program counter and stack.',
        ),
        TranscriptSegment(
          startSec: 100.0,
          endSec: 125.0,
          text:
              'This makes thread switching faster, but developers must use synchronization primitives like mutexes and semaphores to prevent race conditions.',
        ),
      ],
      summary: const QaydSummary(
        overview:
            'This lecture introduces the core concepts of Operating Systems regarding memory architecture, kernel isolation, and key trade-offs between independent Processes and lightweight Threads.',
        sections: [
          SummarySection(
            heading: 'Lecture Introduction',
            startSec: 0.0,
            summary:
                'Frames the comparison between OS processes and threads inside modern operating systems.',
          ),
          SummarySection(
            heading: 'Processes & Kernel Isolation',
            startSec: 15.0,
            summary:
                'Explains dedicated process address spaces (code, data, heap, stack) and IPC via pipes, message queues, or shared memory.',
          ),
          SummarySection(
            heading: 'Threads & Shared Memory',
            startSec: 75.0,
            summary:
                'Defines threads as lightweight processes sharing code and heap while keeping private registers and stack.',
          ),
          SummarySection(
            heading: 'Synchronization Primitives',
            startSec: 100.0,
            summary:
                'Highlights why mutexes and semaphores are needed to prevent race conditions across concurrent threads.',
          ),
        ],
        keyPoints: [
          'A Process is an executing program instance with its own isolated address space (code, data, heap, and stack).',
          'Inter-Process Communication (IPC) via pipes or shared memory is mandatory to exchange data across process boundaries.',
          'Threads are lightweight units of execution within a process that share code and heap memory.',
          'Thread switching overhead is significantly lower than full process context switching.',
          'Shared memory across threads necessitates synchronization primitives (mutexes, semaphores) to eliminate race conditions.',
        ],
        keyTerms: [
          KeyTerm(
            term: 'Process',
            definition:
                'An active instance of a running computer program with dedicated address space and kernel resources.',
          ),
          KeyTerm(
            term: 'Thread',
            definition:
                'A lightweight process (LWP) and basic unit of CPU scheduling sharing memory with sibling threads.',
          ),
          KeyTerm(
            term: 'Context Switch',
            definition:
                'The process of saving the state of an active thread/process and restoring another.',
          ),
          KeyTerm(
            term: 'Race Condition',
            definition:
                'A concurrency defect when multiple execution paths attempt unsynchronized shared memory writes.',
          ),
        ],
      ),
    );

    await storageService.saveQayd(demoQayd);
    _qayds = storageService.getAllQayds();
    _folders = storageService.getAllFolders();
    notifyListeners();
  }

  void filterByFolder(String? folderId) {
    _selectedFolderId = folderId;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Audio Recording Flow (FR1)
  // ---------------------------------------------------------------------------

  /// Starts live microphone recording
  Future<void> startRecording() async {
    try {
      _activeQayd = null;
      _errorMessage = null;
      _errorQaydId = null;
      _processingProgress = 0.0;
      _processingStatusMessage = '';
      _pendingPhotos = [];
      await recordingService.startRecording();
      _isRecording = true;
      _isPaused = false;
      _recordDurationSeconds = 0;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _errorQaydId = null;
      _isRecording = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Pauses active recording
  Future<void> pauseRecording() async {
    await recordingService.pauseRecording();
    _isPaused = true;
    notifyListeners();
  }

  /// Resumes recording
  Future<void> resumeRecording() async {
    await recordingService.resumeRecording();
    _isPaused = false;
    notifyListeners();
  }

  /// Stops recording and triggers the AI processing pipeline
  Future<Qayd> stopRecordingAndProcess({
    String? title,
    String summaryLanguage = 'en',
    String? audioLanguage,
    List<LecturePhoto>? photos,
  }) async {
    // Capture any in-recording photos before clearing the buffer for the next run.
    final finalPhotos = List<LecturePhoto>.from(photos ?? _pendingPhotos);
    _pendingPhotos = [];

    // Clear any previously completed activeQayd synchronously so ProcessingScreen
    // does not immediately auto-navigate to the previous lecture while stopRecording() awaits.
    _activeQayd = null;
    _errorMessage = null;
    _errorQaydId = null;
    _processingProgress = 0.1;
    _processingStatusMessage = 'Saving audio recording...';
    notifyListeners();

    try {
      final audioPath = await recordingService.stopRecording();
      _isRecording = false;
      _isPaused = false;
      final duration = _recordDurationSeconds;
      notifyListeners();

      if (audioPath == null || audioPath.isEmpty) {
        throw Exception('Recording produced no valid audio file.');
      }

      final finalTitle = title?.trim().isNotEmpty == true
          ? title!.trim()
          : 'Lecture ${_qayds.length + 1}';

      return await _runAiPipeline(
        audioPath: audioPath,
        title: finalTitle,
        durationSec: duration,
        folderId: _selectedFolderId,
        summaryLanguage: summaryLanguage,
        audioLanguage: audioLanguage,
        photos: finalPhotos,
      );
    } catch (e) {
      _isRecording = false;
      _isPaused = false;
      _errorMessage = e.toString();
      _errorQaydId = _activeQayd?.id;
      _processingStatusMessage = 'Processing failed.';
      notifyListeners();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Audio Import Flow (FR2)
  // ---------------------------------------------------------------------------

  /// Opens file picker without blocking the UI state; returns `null` if cancelled.
  Future<PickedAudioResult?> pickAudioForImport() {
    return pickerService.pickAudioFile();
  }

  /// Compresses a picked audio file and validates the compressed size (< 100 MB).
  Future<CompressedAudioResult> compressImportedAudio(PickedAudioResult picked) {
    return compressionService.compressToWhisperMp3(picked.path);
  }

  /// Resets processing state synchronously right before pushing ProcessingScreen.
  void prepareForImportProcessing() {
    _activeQayd = null;
    _errorMessage = null;
    _errorQaydId = null;
    _processingProgress = 0.15;
    _processingStatusMessage = 'Preparing compressed audio...';
    notifyListeners();
  }

  /// Runs the AI pipeline for an already compressed audio file.
  Future<Qayd> processCompressedImport({
    required String audioPath,
    required String fileName,
    String? title,
    String summaryLanguage = 'ar',
    String? audioLanguage,
  }) async {
    final finalTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

    return await _runAiPipeline(
      audioPath: audioPath,
      title: finalTitle,
      durationSec: 0, // Will be updated by Whisper duration
      folderId: _selectedFolderId,
      summaryLanguage: summaryLanguage,
      audioLanguage: audioLanguage,
    );
  }

  /// Convenience wrapper that picks, compresses, and processes an imported audio file.
  Future<Qayd?> importAudioAndProcess({
    String? title,
    String summaryLanguage = 'ar',
    String? audioLanguage,
  }) async {
    try {
      final picked = await pickAudioForImport();
      if (picked == null) return null; // User cancelled

      final compressed = await compressImportedAudio(picked);
      prepareForImportProcessing();

      return await processCompressedImport(
        audioPath: compressed.path,
        fileName: picked.fileName,
        title: title,
        summaryLanguage: summaryLanguage,
        audioLanguage: audioLanguage,
      );
    } catch (e) {
      _errorMessage = e.toString();
      _errorQaydId = _activeQayd?.id;
      notifyListeners();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // The Core AI Pipeline (Record/Import -> Transcribe -> Summarize -> Save)
  // ---------------------------------------------------------------------------

  /// Transcribes [audioPath], splitting long/large audio into Whisper-optimal
  /// chunks first so Groq never hits its upload or length limits.
  Future<TranscriptionResult> _transcribeAudio(
    String audioPath,
    String? audioLanguage,
  ) async {
    if (!await splitterService.needsSplitting(audioPath)) {
      return whisperService.transcribeAudio(
        audioFilePath: audioPath,
        customApiKey: _effectiveGroqApiKey,
        audioLanguage: audioLanguage,
      );
    }

    final chunks = await splitterService.splitToWhisperChunks(audioPath);
    return whisperService.transcribeAudioChunked(
      chunkPaths: chunks,
      chunkDurationSec: AudioSplitterService.chunkDurationSec,
      customApiKey: _effectiveGroqApiKey,
      audioLanguage: audioLanguage,
      onChunkProgress: (completed, total) {
        _processingStatusMessage =
            'Transcribing audio part ${completed + 1} of $total...';
        notifyListeners();
      },
    );
  }

  Future<Qayd> _runAiPipeline({
    required String audioPath,
    required String title,
    required int durationSec,
    String? folderId,
    String summaryLanguage = 'ar',
    String? audioLanguage,
    List<LecturePhoto> photos = const [],
  }) async {
    _errorMessage = null;
    _errorQaydId = null;

    // 1. Create initial Qayd in transcribing state
    var qayd = Qayd(
      id: const Uuid().v4(),
      title: title,
      createdAt: DateTime.now(),
      durationSec: durationSec,
      audioPath: audioPath,
      status: QaydStatus.transcribing,
      folderId: folderId,
      summaryLanguage: summaryLanguage,
      photos: photos,
    );
    _activeQayd = qayd;
    _processingStatusMessage = 'Transcribing audio with Groq Whisper...';
    _processingProgress = 0.25;
    notifyListeners();

    try {
      // 2. Transcribe Audio (FR3). Long recordings are split + compressed into
      //    Whisper-optimal chunks, transcribed separately, then merged.
      final transcriptResult = await _transcribeAudio(audioPath, audioLanguage);

      final finalDuration = durationSec > 0
          ? durationSec
          : transcriptResult.durationSec.round();

      // CRITICAL INVARIANT: Save transcript immediately before calling Gemini!
      // If summary fails or hits rate-limit, the transcript is completely safe (NFR3).
      qayd = qayd.copyWith(
        transcript: transcriptResult.text,
        segments: transcriptResult.segments,
        language: transcriptResult.language,
        durationSec: finalDuration,
        status: QaydStatus.transcribed,
      );
      _activeQayd = qayd;
      await storageService.saveQayd(qayd);

      _processingStatusMessage = summaryLanguage == 'ar'
          ? 'جاري توليد الملخص الأكاديمي بالذكاء الاصطناعي...'
          : 'Generating academic summary with Gemini...';
      _processingProgress = 0.65;
      notifyListeners();

      // 3. Generate Summary in User's Requested Language (FR4)
      try {
        final summary = await summaryService.generateSummary(
          transcript: transcriptResult.text,
          segments: transcriptResult.segments,
          summaryLanguage: summaryLanguage,
          customApiKey: _effectiveGeminiApiKey,
        );

        qayd = qayd.copyWith(
          summary: summary,
          status: QaydStatus.done,
          summaryLanguage: summaryLanguage,
        );
        _processingStatusMessage = 'Done!';
        _processingProgress = 1.0;
      } catch (geminiError) {
        // If Gemini fails (e.g. rate limit), keep the Qayd with transcript intact!
        qayd = qayd.copyWith(status: QaydStatus.failed);
        _errorMessage = 'Summary generation failed: $geminiError';
        _errorQaydId = qayd.id;
        _processingStatusMessage = 'Summary failed. Transcript saved safely.';
        _processingProgress = 0.65;
      }

      // 4. Save Final State and Update List (FR6)
      await storageService.saveQayd(qayd);
      _activeQayd = qayd;
      loadInitialData(); // Refresh list
      notifyListeners();

      return qayd;
    } catch (e) {
      qayd = qayd.copyWith(status: QaydStatus.failed);
      await storageService.saveQayd(qayd);
      _activeQayd = qayd;
      _errorMessage = e.toString();
      _errorQaydId = qayd.id;
      _processingStatusMessage = 'Processing failed.';
      loadInitialData();
      notifyListeners();
      rethrow;
    }
  }

  /// Retries summarization for a transcribed Qayd (e.g. after fixing rate limit)
  Future<void> retrySummary(String qaydId, {String? summaryLanguage}) async {
    var qayd = storageService.getQayd(qaydId);
    if (qayd == null) {
      _errorMessage = 'Lecture not found.';
      _errorQaydId = qaydId;
      notifyListeners();
      return;
    }
    if (qayd.transcript.trim().isEmpty) {
      _errorMessage =
          'Cannot generate summary: no transcript available for this lecture.';
      _errorQaydId = qaydId;
      notifyListeners();
      return;
    }

    final targetLang = summaryLanguage ?? qayd.summaryLanguage;

    _isRetryingSummary = true;
    _errorMessage = null;
    _errorQaydId = null;
    _processingProgress = 0.65;
    _processingStatusMessage = targetLang == 'ar'
        ? 'جاري توليد الملخص بالعربية...'
        : 'Regenerating summary with Gemini...';
    notifyListeners();

    try {
      final summary = await summaryService.generateSummary(
        transcript: qayd.transcript,
        segments: qayd.segments,
        summaryLanguage: targetLang,
        customApiKey: _effectiveGeminiApiKey,
      );

      qayd = qayd.copyWith(
        summary: summary,
        status: QaydStatus.done,
        summaryLanguage: targetLang,
      );
      await storageService.saveQayd(qayd);
      _activeQayd = qayd;
      _processingProgress = 1.0;
      _processingStatusMessage = 'Done!';
      loadInitialData();
    } catch (e) {
      _errorMessage = 'Retry failed: $e';
      _errorQaydId = qaydId;
      _processingProgress = 0.65;
    } finally {
      _isRetryingSummary = false;
      notifyListeners();
    }
  }

  /// Convenient helper to regenerate summary in a specific language (EN or AR)
  Future<void> regenerateSummaryWithLanguage(
    String qaydId,
    String languageCode,
  ) async {
    return retrySummary(qaydId, summaryLanguage: languageCode);
  }

  // ---------------------------------------------------------------------------
  // Management & Folder Operations (NFR9, NFR10, NFR11)
  // ---------------------------------------------------------------------------

  /// Renames a Qayd (NFR9)
  Future<void> renameQayd(String id, String newTitle) async {
    final qayd = storageService.getQayd(id);
    if (qayd != null) {
      final updated = qayd.copyWith(title: newTitle.trim());
      await storageService.saveQayd(updated);
      if (_activeQayd?.id == id) {
        _activeQayd = updated;
      }
      loadInitialData();
    }
  }

  /// Deletes a Qayd and its local audio file (NFR9)
  Future<void> deleteQayd(String id) async {
    await storageService.deleteQayd(id);
    if (_activeQayd?.id == id) {
      _activeQayd = null;
    }
    if (_errorQaydId == id) {
      _errorMessage = null;
      _errorQaydId = null;
    }
    loadInitialData();
  }

  /// Edits a single timestamped transcript segment in-place and rebuilds the
  /// full transcript so Tap-to-Seek timestamps remain intact.
  Future<void> editTranscriptSegment(
    String id,
    int segmentIndex,
    String newText,
  ) async {
    final qayd = storageService.getQayd(id);
    final trimmed = newText.trim();
    if (qayd == null ||
        trimmed.isEmpty ||
        segmentIndex < 0 ||
        segmentIndex >= qayd.segments.length) {
      return;
    }

    final updatedSegments = List<TranscriptSegment>.from(qayd.segments);
    final target = updatedSegments[segmentIndex];
    updatedSegments[segmentIndex] = TranscriptSegment(
      startSec: target.startSec,
      endSec: target.endSec,
      text: trimmed,
    );

    final rebuiltTranscript = updatedSegments
        .map((s) => s.text.trim())
        .where((t) => t.isNotEmpty)
        .join(' ');

    final updated = qayd.copyWith(
      transcript: rebuiltTranscript,
      segments: updatedSegments,
    );
    await storageService.saveQayd(updated);
    if (_activeQayd?.id == id) {
      _activeQayd = updated;
    }
    loadInitialData();
  }

  /// Edits the full transcript and saves it (NFR11).
  /// Clears stale timestamped segments only when text actually changed.
  Future<void> editTranscript(String id, String newTranscript) async {
    final qayd = storageService.getQayd(id);
    if (qayd != null) {
      final trimmed = newTranscript.trim();
      final textChanged = trimmed != qayd.transcript.trim();
      final updated = qayd.copyWith(
        transcript: trimmed,
        segments: (qayd.segments.isNotEmpty && textChanged)
            ? const []
            : qayd.segments,
      );
      await storageService.saveQayd(updated);
      if (_activeQayd?.id == id) {
        _activeQayd = updated;
      }
      loadInitialData();
    }
  }

  /// Moves a Qayd to a specific subject folder (or Root when [folderId] is null)
  Future<void> moveQaydToFolder(String qaydId, String? folderId) async {
    final qayd = storageService.getQayd(qaydId);
    if (qayd != null) {
      final updated = qayd.copyWith(
        folderId: folderId,
        clearFolderId: folderId == null,
      );
      await storageService.saveQayd(updated);
      if (_activeQayd?.id == qaydId) {
        _activeQayd = updated;
      }
      loadInitialData();
    }
  }

  /// Creates a new subject folder (NFR10)
  Future<void> createFolder(String name) async {
    if (name.trim().isEmpty) return;
    _hasSeededSession = true;
    final folder = QaydFolder(
      id: const Uuid().v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
    );
    await storageService.saveFolder(folder);
    loadInitialData();
  }

  /// Renames an existing subject folder
  Future<void> renameFolder(String folderId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    for (final folder in storageService.getAllFolders()) {
      if (folder.id == folderId) {
        final updated = QaydFolder(
          id: folder.id,
          name: trimmed,
          createdAt: folder.createdAt,
        );
        await storageService.saveFolder(updated);
        loadInitialData();
        return;
      }
    }
  }

  /// Deletes a folder and safely unfiles all its Qayds
  Future<void> deleteFolder(String folderId) async {
    _hasSeededSession = true;
    await storageService.deleteFolder(folderId);
    if (_selectedFolderId == folderId) {
      _selectedFolderId = null;
    }
    loadInitialData();
  }

  void setActiveQayd(Qayd qayd) {
    _activeQayd = qayd;
    notifyListeners();
  }

  @override
  void dispose() {
    recordingService.dispose();
    super.dispose();
  }
}

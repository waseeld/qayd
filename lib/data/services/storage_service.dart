// ==============================================================================
// Storage Service (Local Persistence via Hive)
// File: lib/data/services/storage_service.dart
//
// Handles offline-first persistence for all Qayds and subject folders.
// Stores serialized JSON maps without needing complicated code generation.
// ==============================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/qayd_model.dart';
import '../models/folder_model.dart';

class StorageService {
  static const String _qaydsBoxName = 'qayds_box';
  static const String _foldersBoxName = 'folders_box';
  static const String _metaBoxName = 'meta_box';
  static const String _demoSeededKey = 'demo_seeded';
  static const String _settingsBoxName = 'settings_box';
  static const String _groqApiKeyKey = 'groq_api_key';
  static const String _geminiApiKeyKey = 'gemini_api_key';

  late Box<Map> _qaydsBox;
  late Box<Map> _foldersBox;
  late Box<bool> _metaBox;
  late Box<String> _settingsBox;
  bool _isInitialized = false;

  /// Initializes Hive database and opens the necessary boxes
  Future<void> init() async {
    await Hive.initFlutter();
    _qaydsBox = await Hive.openBox<Map>(_qaydsBoxName);
    _foldersBox = await Hive.openBox<Map>(_foldersBoxName);
    _metaBox = await Hive.openBox<bool>(_metaBoxName);
    _settingsBox = await Hive.openBox<String>(_settingsBoxName);
    _isInitialized = true;
  }

  /// Whether starter demo content has already been seeded for this installation
  bool get hasSeededDemo {
    if (!_isInitialized) return false;
    return _metaBox.get(_demoSeededKey) ?? false;
  }

  /// Marks starter demo content as seeded so deleted user items never resurrect
  Future<void> markDemoSeeded() async {
    if (!_isInitialized) return;
    await _metaBox.put(_demoSeededKey, true);
  }

  // ---------------------------------------------------------------------------
  // User API Keys (Settings)
  // ---------------------------------------------------------------------------

  /// The Groq Whisper API key saved by the user, or '' when none is set.
  String get groqApiKey {
    if (!_isInitialized) return '';
    return _settingsBox.get(_groqApiKeyKey) ?? '';
  }

  /// The Gemini API key saved by the user, or '' when none is set.
  String get geminiApiKey {
    if (!_isInitialized) return '';
    return _settingsBox.get(_geminiApiKeyKey) ?? '';
  }

  /// Persists both API keys once so the user never has to re-enter them.
  /// Passing empty strings clears the respective key.
  Future<void> saveApiKeys({
    required String groqApiKey,
    required String geminiApiKey,
  }) async {
    if (!_isInitialized) return;
    await _settingsBox.put(_groqApiKeyKey, groqApiKey.trim());
    await _settingsBox.put(_geminiApiKeyKey, geminiApiKey.trim());
  }

  // ---------------------------------------------------------------------------
  // Qayd Operations (FR6, NFR9)
  // ---------------------------------------------------------------------------

  /// Saves or updates a Qayd in local storage
  Future<void> saveQayd(Qayd qayd) async {
    if (!_isInitialized) return;
    await _qaydsBox.put(qayd.id, qayd.toMap());
  }

  /// Retrieves a specific Qayd by its unique ID
  Qayd? getQayd(String id) {
    if (!_isInitialized) return null;
    final map = _qaydsBox.get(id);
    if (map == null) return null;
    return Qayd.fromMap(Map<String, dynamic>.from(map));
  }

  /// Returns all saved Qayds sorted newest-first (FR6)
  List<Qayd> getAllQayds() {
    if (!_isInitialized) return [];
    final qayds = <Qayd>[];
    for (final raw in _qaydsBox.values) {
      try {
        qayds.add(Qayd.fromMap(Map<String, dynamic>.from(raw)));
      } catch (e) {
        debugPrint('Error parsing Qayd from storage: $e');
      }
    }
    // Sort descending by creation date (newest first)
    qayds.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return qayds;
  }

  /// Deletes a Qayd and its local audio/photo files to prevent orphan files (NFR9)
  Future<void> deleteQayd(String id) async {
    if (!_isInitialized) return;
    final qayd = getQayd(id);
    if (qayd != null) {
      final pathsToDelete = <String>[];
      if (qayd.audioPath.isNotEmpty) {
        pathsToDelete.add(qayd.audioPath);
      }
      pathsToDelete.addAll(qayd.photos.map((p) => p.path));
      for (final path in pathsToDelete) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Could not delete file ($path): $e');
        }
      }
    }
    await _qaydsBox.delete(id);
  }

  /// Filters Qayds by subject folder
  List<Qayd> getQaydsByFolder(String? folderId) {
    return getAllQayds().where((q) => q.folderId == folderId).toList();
  }

  // ---------------------------------------------------------------------------
  // Folder Operations (NFR10)
  // ---------------------------------------------------------------------------

  /// Saves a subject folder
  Future<void> saveFolder(QaydFolder folder) async {
    if (!_isInitialized) return;
    await _foldersBox.put(folder.id, folder.toMap());
  }

  /// Returns all folders sorted alphabetically by name
  List<QaydFolder> getAllFolders() {
    if (!_isInitialized) return [];
    final folders = <QaydFolder>[];
    for (final raw in _foldersBox.values) {
      try {
        folders.add(QaydFolder.fromMap(Map<String, dynamic>.from(raw)));
      } catch (e) {
        debugPrint('Error parsing folder: $e');
      }
    }
    folders.sort((a, b) => a.name.compareTo(b.name));
    return folders;
  }

  /// Deletes a folder and unfiles all its Qayds safely
  Future<void> deleteFolder(String folderId) async {
    if (!_isInitialized) return;
    // Unassign all Qayds in this folder before deleting it
    for (final qayd in getQaydsByFolder(folderId)) {
      final updated = qayd.copyWith(clearFolderId: true);
      await saveQayd(updated);
    }
    await _foldersBox.delete(folderId);
  }
}

// ==============================================================================
// Photo Capture Service
// File: lib/data/services/photo_capture_service.dart
//
// Persists photos captured by the in-app camera into durable app storage and
// attaches the recording-relative timestamp (FR-Photos).
// ==============================================================================

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/qayd_model.dart';

class PhotoCaptureService {
  /// Copies a freshly captured photo into app storage and returns a
  /// [LecturePhoto] linked to [takenAtSec] (seconds since recording started).
  Future<LecturePhoto> persistPhoto({
    required String sourcePath,
    required double takenAtSec,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/lecture_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final extension = _extensionOf(sourcePath);
    final destPath =
        '${dir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await File(sourcePath).copy(destPath);

    return LecturePhoto(path: destPath, takenAtSec: takenAtSec);
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    return (ext.isEmpty || ext.length > 5) ? 'jpg' : ext;
  }
}

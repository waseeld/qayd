import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/models/qayd_model.dart';
import 'package:qayd/data/models/folder_model.dart';

void main() {
  group('Qayd Model Tests', () {
    test('TranscriptSegment serialization round-trip', () {
      const segment = TranscriptSegment(
        startSec: 2.74,
        endSec: 8.54,
        text: 'أحد أشهر المفاهيم في البرمجة هو الـ API',
      );

      final map = segment.toMap();
      final recovered = TranscriptSegment.fromMap(map);

      expect(recovered.startSec, 2.74);
      expect(recovered.endSec, 8.54);
      expect(recovered.text, 'أحد أشهر المفاهيم في البرمجة هو الـ API');
    });

    test('QaydSummary with SummarySections & KeyTerms serialization round-trip', () {
      const summary = QaydSummary(
        overview: 'Overview of modern web architecture with APIs.',
        sections: [
          SummarySection(
            heading: 'Introduction to APIs',
            startSec: 15.0,
            summary: 'Defines client-server request/response messaging.',
          ),
        ],
        keyPoints: [
          'APIs separate frontend from backend.',
          'Servers return structured JSON data rather than full HTML pages.',
        ],
        keyTerms: [
          KeyTerm(
            term: 'API',
            definition: 'Application Programming Interface connecting services.',
          ),
        ],
      );

      final map = summary.toMap();
      final recovered = QaydSummary.fromMap(map);

      expect(recovered.overview, summary.overview);
      expect(recovered.sections.length, 1);
      expect(recovered.sections.first.heading, 'Introduction to APIs');
      expect(recovered.sections.first.startSec, 15.0);
      expect(recovered.keyPoints.length, 2);
      expect(recovered.keyTerms.first.term, 'API');

      // Verify backwards compatibility when older Hive maps omit `sections`
      final legacyMap = Map<String, dynamic>.from(map)..remove('sections');
      final legacyRecovered = QaydSummary.fromMap(legacyMap);
      expect(legacyRecovered.sections, isEmpty);
    });

    test('Complete Qayd entity serialization and copyWith (including clearFolderId)', () {
      final now = DateTime.now();
      final qayd = Qayd(
        id: 'qayd-123',
        title: 'Database Architecture Lecture',
        createdAt: now,
        durationSec: 1800,
        audioPath: '/data/audio/lecture1.m4a',
        language: QaydLanguage.mixed,
        transcript: 'Introduction to backend and APIs...',
        segments: const [
          TranscriptSegment(startSec: 0.0, endSec: 4.5, text: 'Hello everyone'),
        ],
        status: QaydStatus.done,
        folderId: 'folder-99',
      );

      final map = qayd.toMap();
      final recovered = Qayd.fromMap(map);

      expect(recovered.id, 'qayd-123');
      expect(recovered.title, 'Database Architecture Lecture');
      expect(recovered.language, QaydLanguage.mixed);
      expect(recovered.segments.length, 1);
      expect(recovered.status, QaydStatus.done);
      expect(recovered.folderId, 'folder-99');

      // Normal copyWith keeps folderId
      final renamed = qayd.copyWith(title: 'Updated Title');
      expect(renamed.title, 'Updated Title');
      expect(renamed.id, 'qayd-123');
      expect(renamed.folderId, 'folder-99');

      // clearFolderId explicitly unfiles Qayd back to Root
      final unfiled = qayd.copyWith(clearFolderId: true);
      expect(unfiled.folderId, isNull);
    });

    test('QaydFolder serialization', () {
      final folder = QaydFolder(
        id: 'folder-1',
        name: 'Mobile Development',
        createdAt: DateTime.now(),
      );

      final map = folder.toMap();
      final recovered = QaydFolder.fromMap(map);

      expect(recovered.id, 'folder-1');
      expect(recovered.name, 'Mobile Development');
    });

    test('LecturePhoto and Qayd.photos serialization with backward compatibility', () {
      final qayd = Qayd(
        id: 'qayd-photo',
        title: 'Photo Lecture',
        createdAt: DateTime.now(),
        durationSec: 300,
        audioPath: '/data/audio/lecture.m4a',
        photos: const [
          LecturePhoto(path: '/data/photos/p1.jpg', takenAtSec: 12.0),
          LecturePhoto(path: '/data/photos/p2.jpg', takenAtSec: 88.5),
        ],
      );

      final map = qayd.toMap();
      final recovered = Qayd.fromMap(map);

      expect(recovered.photos.length, 2);
      expect(recovered.photos.first.path, '/data/photos/p1.jpg');
      expect(recovered.photos.first.takenAtSec, 12.0);
      expect(recovered.photos.last.takenAtSec, 88.5);

      // Legacy Hive maps that omit `photos` default to an empty list
      final legacyMap = Map<String, dynamic>.from(map)..remove('photos');
      final legacy = Qayd.fromMap(legacyMap);
      expect(legacy.photos, isEmpty);
    });
  });
}

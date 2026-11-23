import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/data/models/qayd_model.dart';
import 'package:qayd/data/services/audio_splitter_service.dart';
import 'package:qayd/data/services/groq_whisper_service.dart';

void main() {
  group('AudioSplitterService.parseDurationToSeconds', () {
    test('parses plain FFprobe seconds', () {
      expect(
        AudioSplitterService.parseDurationToSeconds('600.123456'),
        600.123456,
      );
    });

    test('parses HH:MM:SS.mmm durations', () {
      expect(AudioSplitterService.parseDurationToSeconds('00:10:05.000'), 605.0);
      expect(AudioSplitterService.parseDurationToSeconds('01:02:03.500'), 3723.5);
    });

    test('returns null for unknown/empty values', () {
      expect(AudioSplitterService.parseDurationToSeconds(null), null);
      expect(AudioSplitterService.parseDurationToSeconds('N/A'), null);
      expect(AudioSplitterService.parseDurationToSeconds(''), null);
    });
  });

  group('GroqWhisperService.mergeChunkResults', () {
    test('offsets segments and concatenates text across chunks', () {
      final merged = GroqWhisperService.mergeChunkResults(
        const [
          TranscriptionResult(
            text: 'First part.',
            segments: [
              TranscriptSegment(startSec: 0.0, endSec: 5.0, text: 'First part.'),
            ],
            language: QaydLanguage.en,
            durationSec: 5.0,
          ),
          TranscriptionResult(
            text: 'Second part.',
            segments: [
              TranscriptSegment(startSec: 0.0, endSec: 6.0, text: 'Second part.'),
            ],
            language: QaydLanguage.en,
            durationSec: 6.0,
          ),
        ],
        chunkOffsetsSec: const [0.0, 600.0],
      );

      expect(merged.text, 'First part. Second part.');
      expect(merged.segments.length, 2);
      expect(merged.segments[0].startSec, 0.0);
      expect(merged.segments[1].startSec, 600.0);
      expect(merged.segments[1].endSec, 606.0);
      expect(merged.durationSec, 606.0);
      expect(merged.language, QaydLanguage.en);
    });

    test('defaults offsets to chunk index when none supplied', () {
      final merged = GroqWhisperService.mergeChunkResults(
        const [
          TranscriptionResult(
            text: 'A',
            segments: [],
            language: QaydLanguage.en,
            durationSec: 3.0,
          ),
          TranscriptionResult(
            text: 'B',
            segments: [],
            language: QaydLanguage.en,
            durationSec: 4.0,
          ),
        ],
      );

      expect(merged.text, 'A B');
      expect(merged.durationSec, 604.0);
    });

    test('detects mixed language from the merged text', () {
      final merged = GroqWhisperService.mergeChunkResults(
        const [
          TranscriptionResult(
            text: 'السلام عليكم API',
            segments: [],
            language: QaydLanguage.en,
            durationSec: 2.0,
          ),
        ],
        chunkOffsetsSec: const [0.0],
      );

      expect(merged.language, QaydLanguage.mixed);
    });
  });
}

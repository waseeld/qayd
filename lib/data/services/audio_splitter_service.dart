// ==============================================================================
// Audio Splitter Service
// File: lib/data/services/audio_splitter_service.dart
//
// Splits long audio recordings/imports into Whisper-optimal chunks so Groq
// Whisper never hits its upload limit or practical length ceiling.
// Each chunk is encoded in one pass to 16 kHz Mono 32 kbps MP3 using the
// FFmpeg segment muxer (10-minute chunks).
// ==============================================================================

import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';

class AudioSplitterService {
  /// Maximum duration of a single chunk before splitting (10 minutes).
  static const int chunkDurationSec = 600;

  /// Rough compressed size above which we split even when duration is unknown.
  /// Kept comfortably under Groq's 25 MB Free Tier upload limit.
  static const int maxSingleChunkBytes = 24 * 1024 * 1024;

  /// Decides whether [inputPath] is too long/large for a single Whisper request.
  Future<bool> needsSplitting(String inputPath) async {
    final durationSec = await probeDurationSec(inputPath);
    if (durationSec != null && durationSec > chunkDurationSec) {
      return true;
    }

    // Fallback: split by size when duration cannot be probed (e.g. SAF URI).
    try {
      final file = File(inputPath);
      if (await file.exists()) {
        return await file.length() > maxSingleChunkBytes;
      }
    } catch (_) {
      // MissingPluginException in tests, or a content:// path — assume not split.
    }
    return false;
  }

  /// Splits [inputPath] into compressed 16 kHz Mono 32 kbps MP3 chunks.
  /// Returns the chunk file paths in chronological order.
  Future<List<String>> splitToWhisperChunks(String inputPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${appDir.path}/audio_chunks/${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Resolve Android SAF content:// URIs if returned directly by a picker.
    final effectiveInput =
        (Platform.isAndroid && inputPath.startsWith('content://'))
            ? (await FFmpegKitConfig.getSafParameterForRead(inputPath) ??
                inputPath)
            : inputPath;

    final outputPattern = '${dir.path}/chunk_%04d.mp3';
    final completer = Completer<FFmpegSession>();

    await FFmpegKit.executeWithArgumentsAsync(
      [
        '-y',
        '-i',
        effectiveInput,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-b:a',
        '32k',
        '-f',
        'segment',
        '-segment_time',
        '$chunkDurationSec',
        '-reset_timestamps',
        '1',
        outputPattern,
      ],
      (FFmpegSession session) {
        if (!completer.isCompleted) {
          completer.complete(session);
        }
      },
    );

    final session = await completer.future;
    final returnCode = await session.getReturnCode();

    final chunks = <String>[];
    if (dir.existsSync()) {
      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.endsWith('.mp3')) {
          chunks.add(entity.path);
        }
      }
      chunks.sort();
    }

    if (!ReturnCode.isSuccess(returnCode) || chunks.isEmpty) {
      throw Exception(
        'Could not split this audio file into transcribable chunks.',
      );
    }

    return chunks;
  }

  /// Probes audio duration in seconds via FFprobe. Returns null when the
  /// duration is unavailable (unsupported file, plugin missing in tests, etc.).
  Future<double?> probeDurationSec(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final info = session.getMediaInformation();
      return parseDurationToSeconds(info?.getDuration());
    } catch (_) {
      return null;
    }
  }

  /// Parses FFprobe duration strings such as "600.123456" or "00:10:00.000".
  /// Returns null for empty/unknown values (e.g. "N/A").
  static double? parseDurationToSeconds(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty || value.toLowerCase() == 'n/a') return null;

    // "HH:MM:SS.mmm" form
    final colonParts = value.split(':');
    if (colonParts.length >= 2) {
      try {
        final hours = int.parse(colonParts[0]);
        final minutes = int.parse(colonParts[1]);
        final seconds = double.parse(colonParts[2]);
        return hours * 3600 + minutes * 60 + seconds;
      } catch (_) {
        return null;
      }
    }

    // Plain seconds form
    return double.tryParse(value);
  }
}

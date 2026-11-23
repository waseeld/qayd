// ==============================================================================
// Record Screen (S2)
// File: lib/screens/record/record_screen.dart
//
// Live lecture recording interface with elapsed timer and controls (FR1).
// Allows pausing, resuming, and stopping to trigger AI processing.
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/qayd_model.dart';
import '../../providers/qayd_provider.dart';
import '../processing/processing_screen.dart';
import 'photo_capture_screen.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final TextEditingController _titleController = TextEditingController();
  String _summaryLanguage = 'ar';

  @override
  void initState() {
    super.initState();
    // Automatically start recording when entering the screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<QaydProvider>();
      if (!provider.isRecording) {
        provider.startRecording().catchError((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to start recording: $error')),
            );
            Navigator.pop(context);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onStopPressed() async {
    final provider = context.read<QaydProvider>();

    // Navigate to processing screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const ProcessingScreen(),
      ),
    );

    // Trigger pipeline in background with user selected summary language
    try {
      final title = _titleController.text.trim();
      await provider.stopRecordingAndProcess(
        title: title.isNotEmpty ? title : null,
        summaryLanguage: _summaryLanguage,
        photos: provider.pendingPhotos,
      );
    } catch (_) {
      // Errors are caught and handled inside ProcessingScreen via provider
    }
  }

  Future<void> _onCapturePhotoPressed() async {
    final provider = context.read<QaydProvider>();
    final captured = await Navigator.push<List<LecturePhoto>>(
      context,
      MaterialPageRoute(
        builder: (_) => const PhotoCaptureScreen(),
      ),
    );
    if (captured == null || !mounted) return;
    provider.addPendingPhotos(captured);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<QaydProvider>();
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'تسجيل محاضرة جديدة' : 'Record Lecture'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              // Optional Lecture Title Input
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: isArabic ? 'عنوان المحاضرة (اختياري)' : 'Lecture Title (Optional)',
                  hintText: isArabic ? 'مثال: قواعد البيانات - المحاضرة 4' : 'e.g. Database Systems - Week 4',
                  prefixIcon: const Icon(Icons.edit_note),
                ),
              ),
              const SizedBox(height: 16),

              // Summary Language Selector (AR / EN)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.translate,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              isArabic ? 'لغة التلخيص:' : 'Summary Language:',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 'ar',
                          label: Text('العربية'),
                        ),
                        ButtonSegment(
                          value: 'en',
                          label: Text('English'),
                        ),
                      ],
                      selected: {_summaryLanguage},
                      onSelectionChanged: (newSelection) {
                        setState(() {
                          _summaryLanguage = newSelection.first;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // Pulsing Recording Visual Indicator
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    width: provider.isPaused ? 130 : 160,
                    height: provider.isPaused ? 130 : 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: provider.isPaused
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    ),
                  ),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: provider.isPaused
                          ? theme.colorScheme.outlineVariant
                          : theme.colorScheme.primary,
                    ),
                    child: Icon(
                      provider.isPaused ? Icons.pause : Icons.mic,
                      size: 50,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Elapsed Time Display
              Text(
                _formatDuration(provider.recordDurationSeconds),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                provider.isPaused
                    ? (isArabic ? 'التسجيل موقوف مؤقتاً' : 'Recording Paused')
                    : (isArabic ? 'جاري التسجيل...' : 'Recording in progress...'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 24),

              // Capture photo of the board/slide, linked to the current time
              OutlinedButton.icon(
                onPressed: _onCapturePhotoPressed,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(
                  provider.pendingPhotos.isEmpty
                      ? (isArabic ? 'التقاط صورة' : 'Capture Photo')
                      : '${isArabic ? 'التقاط صورة' : 'Capture Photo'} (${provider.pendingPhotos.length})',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),

              const Spacer(),

              // Control Buttons (Pause/Resume & Stop)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pause / Resume Button
                  OutlinedButton.icon(
                    onPressed: () {
                      if (provider.isPaused) {
                        provider.resumeRecording();
                      } else {
                        provider.pauseRecording();
                      }
                    },
                    icon: Icon(
                      provider.isPaused ? Icons.play_arrow : Icons.pause,
                    ),
                    label: Text(
                      provider.isPaused
                          ? (isArabic ? 'استئناف' : 'Resume')
                          : (isArabic ? 'إيقاف مؤقت' : 'Pause'),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),

                  // Stop & Process Button
                  FilledButton.icon(
                    onPressed: _onStopPressed,
                    icon: const Icon(Icons.stop),
                    label: Text(isArabic ? 'إنهاء وحفظ' : 'Stop & Save'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

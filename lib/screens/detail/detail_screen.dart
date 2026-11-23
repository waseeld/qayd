// ==============================================================================
// Lecture Detail Screen (S4)
// File: lib/screens/detail/detail_screen.dart
//
// Displays the lecture's audio player, English academic summary (FR4),
// and timestamped transcript with interactive "Tap-to-Seek" (FR8).
// ==============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../../data/models/qayd_model.dart';
import '../../data/services/pdf_export_service.dart';
import '../../providers/qayd_provider.dart';
import '../../widgets/qayd_actions.dart';

class DetailScreen extends StatefulWidget {
  final String qaydId;

  const DetailScreen({
    super.key,
    required this.qaydId,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late AudioPlayer _audioPlayer;

  double _currentPositionSec = 0.0;
  double _playbackSpeed = 1.0;
  bool _audioAvailable = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _audioPlayer = AudioPlayer();

    _initAudioPlayer();
  }

  void _initAudioPlayer() async {
    final provider = context.read<QaydProvider>();
    final qayd = provider.qayds.cast<Qayd?>().firstWhere(
      (q) => q?.id == widget.qaydId,
      orElse: () => provider.activeQayd?.id == widget.qaydId
          ? provider.activeQayd
          : provider.storageService.getQayd(widget.qaydId),
    );

    if (qayd == null) return;

    if (qayd.audioPath.isNotEmpty && await File(qayd.audioPath).exists()) {
      try {
        await _audioPlayer.setFilePath(qayd.audioPath);
        if (mounted) setState(() => _audioAvailable = true);

        // Track live audio position for Tap-to-Seek segment highlighting (FR8)
        _audioPlayer.positionStream.listen((position) {
          if (mounted) {
            setState(() {
              _currentPositionSec = position.inMilliseconds / 1000.0;
            });
          }
        });
      } catch (e) {
        debugPrint('Could not load audio file: $e');
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatTime(double seconds) {
    final totalSec = seconds.toInt();
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _seekToSeconds(double seconds) {
    if (_audioAvailable) {
      _audioPlayer.seek(
        Duration(milliseconds: (seconds * 1000).round()),
      );
      if (!_audioPlayer.playing) {
        _audioPlayer.play();
      }
    }
  }

  void _togglePlaybackSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.25;
      } else if (_playbackSpeed == 1.25) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
      _audioPlayer.setSpeed(_playbackSpeed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<QaydProvider>();
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    final qayd = provider.qayds.cast<Qayd?>().firstWhere(
      (q) => q?.id == widget.qaydId,
      orElse: () => provider.activeQayd?.id == widget.qaydId
          ? provider.activeQayd
          : provider.storageService.getQayd(widget.qaydId),
    );

    if (qayd == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(isArabic ? 'المحاضرة غير موجودة' : 'Qayd not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          qayd.title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: isArabic ? 'تصدير PDF' : 'Export PDF',
            onPressed: () => _showPdfExportSheet(context, qayd, isArabic),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(value, qayd),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'export_pdf',
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, size: 20),
                    const SizedBox(width: 10),
                    Text(isArabic ? 'تصدير PDF' : 'Export PDF'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 20),
                    const SizedBox(width: 10),
                    Text(isArabic ? 'إعادة التسمية' : 'Rename'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'edit_transcript',
                child: Row(
                  children: [
                    const Icon(Icons.description, size: 20),
                    const SizedBox(width: 10),
                    Text(isArabic ? 'تعديل النص' : 'Edit Transcript'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'folder',
                child: Row(
                  children: [
                    const Icon(Icons.folder, size: 20),
                    const SizedBox(width: 10),
                    Text(isArabic ? 'نقل إلى مجلد' : 'Move to Folder'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: theme.colorScheme.error),
                    const SizedBox(width: 10),
                    Text(
                      isArabic ? 'حذف' : 'Delete',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.secondary,
          tabs: [
            Tab(
              icon: const Icon(Icons.auto_awesome),
              text: isArabic ? 'الملخص الأكاديمي' : 'Academic Summary',
            ),
            Tab(
              icon: const Icon(Icons.subtitles),
              text: isArabic ? 'التفريغ النصي' : 'Full Transcript',
            ),
            Tab(
              icon: const Icon(Icons.photo_library_outlined),
              text: isArabic ? 'الصور' : 'Photos',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Audio Player Header Bar (FR8)
          if (_audioAvailable) _buildAudioPlayerBar(theme, qayd),

          // Content Tabs (Summary & Transcript)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(theme, qayd, isArabic),
                _buildTranscriptTab(theme, qayd, isArabic),
                _buildPhotosTab(theme, qayd, isArabic),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Audio Player Bar Widget (FR8)
  // ---------------------------------------------------------------------------
  Widget _buildAudioPlayerBar(ThemeData theme, Qayd qayd) {
    final totalDurationSec =
        (_audioPlayer.duration?.inMilliseconds ?? (qayd.durationSec * 1000)) /
            1000.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Row(
            children: [
              StreamBuilder<PlayerState>(
                stream: _audioPlayer.playerStateStream,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data?.playing ?? false;
                  return IconButton.filledTonal(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () {
                      if (isPlaying) {
                        _audioPlayer.pause();
                      } else {
                        _audioPlayer.play();
                      }
                    },
                  );
                },
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(_currentPositionSec),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _currentPositionSec.clamp(0.0, totalDurationSec),
                    max: totalDurationSec > 0 ? totalDurationSec : 1.0,
                    onChanged: (val) {
                      _audioPlayer.seek(
                        Duration(milliseconds: (val * 1000).round()),
                      );
                    },
                  ),
                ),
              ),
              Text(
                _formatTime(totalDurationSec),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              // Playback Speed Toggle (1.0x, 1.25x, 1.5x, 2.0x)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _togglePlaybackSpeed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Academic Summary View (FR4)
  // ---------------------------------------------------------------------------
  Widget _buildSummaryTab(ThemeData theme, Qayd qayd, bool isArabic) {
    final summary = qayd.summary;
    final provider = context.watch<QaydProvider>();
    final isGenerating = provider.isRetryingSummary;
    final hasTranscript = qayd.transcript.trim().isNotEmpty;

    final showScopedError = provider.errorMessage != null &&
        provider.errorQaydId == qayd.id &&
        !isGenerating;

    if (summary == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notes, size: 64, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 16),
              Text(
                isArabic ? 'الملخص غير متوفر بعد' : 'Summary Not Available',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                !hasTranscript
                    ? (isArabic
                        ? 'يرجى تفريغ الصوت أو إضافة نص المحاضرة أولاً قبل توليد الملخص الأكاديمي'
                        : 'Please transcribe the lecture audio or add a transcript first before generating a summary.')
                    : (isArabic
                        ? 'يمكنك إنشاء الملخص الأكاديمي الآن باستخدام Gemini'
                        : 'You can generate the academic summary now with Gemini'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (showScopedError) ...[
                const SizedBox(height: 12),
                Text(
                  provider.errorMessage!,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: (!hasTranscript || isGenerating)
                    ? null
                    : () => context.read<QaydProvider>().retrySummary(qayd.id),
                icon: isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  isGenerating
                      ? (isArabic ? 'جاري توليد الملخص...' : 'Generating Summary...')
                      : (isArabic ? 'توليد الملخص الآن' : 'Generate Summary Now'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isSummaryArabic = qayd.summaryLanguage == 'ar';

    return Directionality(
      textDirection: isSummaryArabic ? TextDirection.rtl : TextDirection.ltr,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Summary Language Indicator & Switcher Bar
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
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
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isArabic ? 'لغة الملخص:' : 'Summary Language:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
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
                  selected: {qayd.summaryLanguage},
                  onSelectionChanged: isGenerating
                      ? null
                      : (newSelection) {
                          final selected = newSelection.first;
                          if (selected != qayd.summaryLanguage) {
                            _confirmRegenerateLanguage(
                              context,
                              qayd,
                              selected,
                              isArabic,
                            );
                          }
                        },
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ],
            ),
          ),

          // Overview Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.menu_book,
                          color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isSummaryArabic ? 'النظرة العامة' : 'Overview',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: isArabic ? 'نسخ الملخص' : 'Copy Summary',
                        icon: const Icon(Icons.content_copy, size: 20),
                        onPressed: () =>
                            _copySummaryToClipboard(qayd, summary, isArabic),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summary.overview,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Topic Breakdown Sections Card
          if (summary.sections.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.view_agenda_outlined,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSummaryArabic ? 'المحاور والموضوعات' : 'Topic Breakdown',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...summary.sections.map(
                      (section) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  InkWell(
                                    onTap: _audioAvailable
                                        ? () =>
                                            _seekToSeconds(section.startSec)
                                        : null,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _audioAvailable
                                            ? theme.colorScheme.primaryContainer
                                            : theme.colorScheme
                                                .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_audioAvailable) ...[
                                            Icon(
                                              Icons.play_arrow,
                                              size: 13,
                                              color: theme.colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                            const SizedBox(width: 2),
                                          ],
                                          Text(
                                            _formatTime(section.startSec),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: _audioAvailable
                                                  ? theme.colorScheme
                                                      .onPrimaryContainer
                                                  : theme.colorScheme
                                                      .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      section.heading,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                section.summary,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Key Points Card
          if (summary.keyPoints.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.checklist,
                            color: theme.colorScheme.secondary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isSummaryArabic
                              ? 'أهم النقاط المستفادة'
                              : 'Key Points & Takeaways',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...summary.keyPoints.map(
                      (point) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 18,
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                point,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Key Terms & Definitions Card
          if (summary.keyTerms.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: theme.colorScheme.tertiary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSummaryArabic
                              ? 'المصطلحات والمفاهيم العلمية'
                              : 'Key Terminology',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...summary.keyTerms.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.term,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.definition,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _copySummaryToClipboard(
    Qayd qayd,
    QaydSummary summary,
    bool isArabic,
  ) async {
    final buffer = StringBuffer()
      ..writeln(qayd.title)
      ..writeln()
      ..writeln('OVERVIEW')
      ..writeln(summary.overview);

    if (summary.sections.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('TOPIC BREAKDOWN');
      for (final section in summary.sections) {
        buffer.writeln(
          '[${_formatTime(section.startSec)}] ${section.heading}: ${section.summary}',
        );
      }
    }

    if (summary.keyPoints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('KEY TAKEAWAYS');
      for (final point in summary.keyPoints) {
        buffer.writeln('• $point');
      }
    }

    if (summary.keyTerms.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('KEY TERMINOLOGY');
      for (final term in summary.keyTerms) {
        buffer.writeln('- ${term.term}: ${term.definition}');
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isArabic ? 'تم نسخ الملخص إلى الحافظة' : 'Summary copied to clipboard',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Full Transcript with Tap-to-Seek & Highlighting (FR3, FR8)
  // ---------------------------------------------------------------------------
  Widget _buildTranscriptTab(ThemeData theme, Qayd qayd, bool isArabic) {
    if (qayd.segments.isEmpty && qayd.transcript.isEmpty) {
      return Center(
        child: Text(isArabic ? 'لا يوجد تفريغ نصي' : 'No transcript available'),
      );
    }

    // If segments exist, render interactive Tap-to-Seek list (FR8)
    if (qayd.segments.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
        itemCount: qayd.segments.length,
        itemBuilder: (context, index) {
          final seg = qayd.segments[index];
          final isPlayingNow = _currentPositionSec >= seg.startSec &&
              _currentPositionSec <= seg.endSec;

          return InkWell(
            onTap: () => _seekToSeconds(seg.startSec),
            onLongPress: () => _showEditSegmentDialog(qayd, index, seg, isArabic),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(vertical: 4.0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isPlayingNow
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.7)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isPlayingNow
                    ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timestamp Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isPlayingNow
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _formatTime(seg.startSec),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isPlayingNow
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Segment Text
                  Expanded(
                    child: Text(
                      seg.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        fontWeight:
                            isPlayingNow ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: isArabic ? 'تعديل المقطع' : 'Edit Segment',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _showEditSegmentDialog(qayd, index, seg, isArabic),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    // Fallback: Raw scrollable text
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: SelectableText(
        qayd.transcript,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Captured Photos linked to their recording timestamps (FR-Photos)
  // ---------------------------------------------------------------------------
  Widget _buildPhotosTab(ThemeData theme, Qayd qayd, bool isArabic) {
    if (qayd.photos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 64,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                isArabic ? 'لا توجد صور لهذه المحاضرة' : 'No photos for this lecture',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? 'التقط صوراً أثناء التسجيل لتظهر هنا مرتبطة بوقت التقاطها'
                    : 'Capture photos while recording and they will appear here, linked to their capture time.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: qayd.photos.length,
      itemBuilder: (context, index) {
        final photo = qayd.photos[index];
        return _buildPhotoTile(theme, photo, isArabic);
      },
    );
  }

  Widget _buildPhotoTile(ThemeData theme, LecturePhoto photo, bool isArabic) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openPhotoViewer(photo, isArabic),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(photo.path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: InkWell(
                onTap: _audioAvailable
                    ? () => _seekToSeconds(photo.takenAtSec)
                    : null,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _audioAvailable
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_audioAvailable) ...[
                        Icon(
                          Icons.play_arrow,
                          size: 13,
                          color: theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 2),
                      ],
                      Text(
                        _formatTime(photo.takenAtSec),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _audioAvailable
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPhotoViewer(LecturePhoto photo, bool isArabic) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.black,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.file(
                      File(photo.path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_audioAvailable)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _seekToSeconds(photo.takenAtSec);
                          },
                          icon:
                              const Icon(Icons.play_arrow, color: Colors.white),
                          label: Text(
                            '${isArabic ? 'تشغيل من' : 'Play from'} ${_formatTime(photo.takenAtSec)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditSegmentDialog(
    Qayd qayd,
    int segmentIndex,
    TranscriptSegment segment,
    bool isArabic,
  ) {
    final controller = TextEditingController(text: segment.text);
    final provider = context.read<QaydProvider>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isArabic
              ? 'تعديل المقطع [${_formatTime(segment.startSec)}]'
              : 'Edit Segment [${_formatTime(segment.startSec)}]',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                provider.editTranscriptSegment(
                  qayd.id,
                  segmentIndex,
                  controller.text,
                );
              }
              Navigator.pop(ctx);
            },
            child: Text(isArabic ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Action Handlers (Export PDF, Rename, Move, Edit, Delete)
  // ---------------------------------------------------------------------------
  void _handleMenuAction(String action, Qayd qayd) {
    if (action == 'export_pdf') {
      final isArabic = Localizations.localeOf(context).languageCode == 'ar';
      _showPdfExportSheet(context, qayd, isArabic);
    } else if (action == 'rename') {
      showRenameQaydDialog(context, qayd);
    } else if (action == 'edit_transcript') {
      showEditTranscriptDialog(context, qayd);
    } else if (action == 'folder') {
      showMoveToFolderDialog(context, qayd);
    } else if (action == 'delete') {
      final navigator = Navigator.of(context);
      showDeleteQaydDialog(
        context,
        qayd,
        beforeDelete: () async {
          try {
            await _audioPlayer.stop();
          } catch (_) {
            // Audio plugin may be unavailable in headless tests or uninitialized state
          }
        },
        onDeleted: () {
          if (mounted) {
            navigator.pop();
          }
        },
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PDF Export Sheet & Handler (FR-PDF)
  // ---------------------------------------------------------------------------
  void _showPdfExportSheet(BuildContext context, Qayd qayd, bool isArabic) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'تصدير مستند PDF' : 'Export PDF Document',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 14),

              // 1. Academic Summary PDF
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                ),
                title: Text(
                  isArabic ? 'تصدير الملخص الأكاديمي' : 'Export Academic Summary',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  isArabic
                      ? 'مذكرة دراسية تشمل النظرة العامة والمحاور والنقاط والمصطلحات'
                      : 'Overview, topic breakdown, takeaways, and key terms',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportPdf(qayd, PdfExportType.summary, isArabic);
                },
              ),

              // 2. Full Transcript PDF
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.subtitles, color: Colors.white, size: 20),
                ),
                title: Text(
                  isArabic ? 'تصدير التفريغ الصوتي الكامل' : 'Export Full Transcript',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  isArabic
                      ? 'النص الكامل للمحاضرة مرمزاً بالطوابع الزمنية الدقيقة'
                      : 'Verbatim transcript with timestamped segments [MM:SS]',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportPdf(qayd, PdfExportType.transcript, isArabic);
                },
              ),

              // 3. Complete Lecture Notes PDF
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.menu_book, color: Colors.white, size: 20),
                ),
                title: Text(
                  isArabic ? 'تصدير المذكرة الشاملة' : 'Export Complete Lecture Notes',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  isArabic
                      ? 'ملف جامع يضم كلاً من الملخص الأكاديمي والتفريغ الصوتي'
                      : 'Comprehensive bundle including both Summary & Transcript',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportPdf(qayd, PdfExportType.full, isArabic);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportPdf(
    Qayd qayd,
    PdfExportType type,
    bool isArabic,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(isArabic ? 'جاري إعداد مستند الـ PDF...' : 'Preparing PDF document...'),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final safeTitle = qayd.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF-]'), '_');
      Uint8List bytes;
      String filename;

      switch (type) {
        case PdfExportType.summary:
          bytes = await PdfExportService.generateSummaryPdf(qayd);
          filename = 'Qayd_Summary_$safeTitle.pdf';
          break;
        case PdfExportType.transcript:
          bytes = await PdfExportService.generateTranscriptPdf(qayd);
          filename = 'Qayd_Transcript_$safeTitle.pdf';
          break;
        case PdfExportType.full:
          bytes = await PdfExportService.generateFullLecturePdf(qayd);
          filename = 'Qayd_Complete_$safeTitle.pdf';
          break;
      }

      await PdfExportService.sharePdf(
        bytes: bytes,
        filename: filename,
        subject: qayd.title,
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'فشل تصدير ملف الـ PDF: $e'
                  : 'Failed to export PDF: $e',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _confirmRegenerateLanguage(
    BuildContext context,
    Qayd qayd,
    String targetLang,
    bool isArabic,
  ) {
    final provider = context.read<QaydProvider>();
    final targetName = targetLang == 'ar' ? 'العربية' : 'English';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isArabic ? 'تغيير لغة الملخص الأكاديمي' : 'Switch Summary Language',
        ),
        content: Text(
          isArabic
              ? 'هل ترغب في إعادة توليد الملخص الأكاديمي باللغة ($targetName) بواسطة ذكاء Gemini الاصطناعي؟'
              : 'Would you like to regenerate the academic summary in $targetName using Gemini AI?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.regenerateSummaryWithLanguage(qayd.id, targetLang);
            },
            child: Text(isArabic ? 'توليد' : 'Generate'),
          ),
        ],
      ),
    );
  }
}

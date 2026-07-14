import 'dart:async';

import 'package:flutter/material.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/video_import/application/video_import_controller.dart';
import 'package:clutter/features/video_import/data/ffmpeg_audio_extraction_service.dart';
import 'package:clutter/features/video_import/data/platform_video_picker.dart';
import 'package:clutter/features/video_import/domain/video_import_models.dart';
import 'package:clutter/features/video_import/presentation/extracted_song_editor.dart';
import 'package:clutter/shared/services/log.dart';

Future<void> runVideoImport(
  BuildContext context,
  MusicLibrary library, {
  VideoPicker? picker,
  AudioExtractionService? extractor,
}) async {
  final videoPicker = picker ?? PlatformVideoPicker();
  final extraction = extractor ?? FfmpegAudioExtractionService();
  SelectedVideo? video;
  try {
    video = await videoPicker.pick();
  } catch (error) {
    Log.e('video picker failed', error);
    library.showToast('could not open the video library');
    return;
  }
  if (video == null || !context.mounted) return;
  final result = await showDialog<_ExtractionResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExtractionDialog(video: video!, extraction: extraction),
  );
  if (result == null || result.cancelled) return;
  if (result.error != null) {
    Log.e('video audio extraction failed', result.error!);
    library.showToast(_errorMessage(result.error!));
    return;
  }
  final audio = result.audio!;
  if (!context.mounted) {
    await extraction.removeTemporaryFile(audio.path);
    return;
  }
  final saved = await showExtractedSongEditor(context, audio, library);
  // rust removes the temporary mp3 after save, dart owns abandoned outputs
  if (!saved) {
    try {
      await extraction.removeTemporaryFile(audio.path);
    } catch (error) {
      Log.e('temporary extracted audio cleanup failed', error);
      library.showToast('could not clean up the temporary audio');
    }
  }
}

String _errorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('no audio')) return 'the selected video has no audio';
  if (message.contains('read the selected')) return 'could not read the video';
  return 'could not extract audio from the video';
}

class _ExtractionDialog extends StatefulWidget {
  final SelectedVideo video;
  final AudioExtractionService extraction;

  const _ExtractionDialog({required this.video, required this.extraction});

  @override
  State<_ExtractionDialog> createState() => _ExtractionDialogState();
}

class _ExtractionDialogState extends State<_ExtractionDialog> {
  late final VideoImportController _controller = VideoImportController(
    widget.extraction,
  );
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    unawaited(_extract());
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _extract() async {
    try {
      final audio = await _controller.extract(widget.video);
      if (mounted) Navigator.of(context).pop(_ExtractionResult.audio(audio));
    } on ExtractionCancelled {
      if (mounted) {
        Navigator.of(context).pop(const _ExtractionResult.cancelled());
      }
    } catch (error) {
      if (mounted) Navigator.of(context).pop(_ExtractionResult.error(error));
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    await _controller.cancel();
    if (mounted && _controller.progress == null) {
      Navigator.of(context).pop(const _ExtractionResult.cancelled());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('import from video'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.video.name, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _controller.progress),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_stageLabel(_controller.stage)),
                if (_controller.progress != null)
                  Text('${(_controller.progress! * 100).round()}%'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancelling ? null : _cancel,
          child: const Text('cancel'),
        ),
      ],
    ),
  );

  String _stageLabel(VideoImportStage stage) => switch (stage) {
    VideoImportStage.inspecting => 'checking video…',
    VideoImportStage.extracting => 'extracting audio…',
    VideoImportStage.cancelling => 'cancelling…',
  };
}

class _ExtractionResult {
  final ExtractedAudio? audio;
  final Object? error;
  final bool cancelled;

  const _ExtractionResult.audio(this.audio) : error = null, cancelled = false;
  const _ExtractionResult.error(this.error) : audio = null, cancelled = false;
  const _ExtractionResult.cancelled()
    : audio = null,
      error = null,
      cancelled = true;
}

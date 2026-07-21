import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:clutter/features/audio_crop/application/audio_crop_controller.dart';
import 'package:clutter/features/audio_crop/data/audioplayers_crop_preview.dart';
import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';

Future<AudioCropSelection?> showAudioCropEditor(
  BuildContext context, {
  required String sourcePath,
  required AudioCropService service,
  required VoidCallback onPreviewStarted,
  Duration? initialStart,
  Duration? initialEnd,
}) async {
  final controller = AudioCropController(
    sourcePath: sourcePath,
    service: service,
    preview: AudioplayersCropPreview(),
    onPreviewStarted: onPreviewStarted,
    initialStart: initialStart,
    initialEnd: initialEnd,
  );
  final editor = AudioCropEditor(controller: controller);
  try {
    if (MediaQuery.sizeOf(context).width < 700) {
      return await Navigator.of(context).push<AudioCropSelection>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => editor),
      );
    }
    return await showDialog<AudioCropSelection>(
      context: context,
      builder: (_) => editor,
    );
  } finally {
    await controller.close();
    controller.dispose();
  }
}

class AudioCropEditor extends StatefulWidget {
  const AudioCropEditor({super.key, required this.controller});

  final AudioCropController controller;

  @override
  State<AudioCropEditor> createState() => _AudioCropEditorState();
}

class _AudioCropEditorState extends State<AudioCropEditor> {
  AudioCropController get _controller => widget.controller;
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _startFocus = FocusNode();
  final _endFocus = FocusNode();
  String? _startError;
  String? _endError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    unawaited(_controller.initialize());
  }

  void _refresh() {
    if (!mounted) return;
    _syncTimeFields();
    setState(() {});
  }

  void _syncTimeFields() {
    if (_controller.loading || _controller.info == null) return;
    if (_startFocus.hasFocus || _endFocus.hasFocus) {
      // active text fields keep their unfinished value until submit
      return;
    }
    _start.text = formatCropTimestamp(_controller.start);
    _end.text = formatCropTimestamp(_controller.end);
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _start.dispose();
    _end.dispose();
    _startFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(width: 720, child: _body());
    if (MediaQuery.sizeOf(context).width < 700) {
      return Scaffold(
        appBar: AppBar(title: const Text('crop audio')),
        body: SafeArea(
          child: Padding(padding: const EdgeInsets.all(16), child: content),
        ),
      );
    }
    return AlertDialog(title: const Text('crop audio'), content: content);
  }

  Widget _body() {
    if (_controller.loading) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_controller.error != null) {
      return _errorBody();
    }
    _syncTimeFields();
    final info = _controller.info!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AudioCropTimeline(
            waveformPath: info.waveformPath,
            duration: info.duration,
            start: _controller.start,
            end: _controller.end,
            position: _controller.position,
            onInteractionStart: _controller.beginBoundaryEdit,
            onInteractionEnd: _controller.endBoundaryEdit,
            onStartChanged: _controller.setStart,
            onEndChanged: _controller.setEnd,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _timeField(_start, 'start', true)),
              const SizedBox(width: 12),
              Expanded(child: _timeField(_end, 'end', false)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'selected ${formatCropTimestamp(_controller.end - _controller.start)}',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                tooltip: _controller.playing ? 'pause preview' : 'play preview',
                onPressed: _controller.previewBusy
                    ? null
                    : _controller.togglePreview,
                icon: _controller.previewBusy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _controller.playing ? Icons.pause : Icons.play_arrow,
                      ),
              ),
              TextButton(
                onPressed: _controller.reset,
                child: const Text('reset'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _controller.selection),
                child: const Text('apply'),
              ),
            ],
          ),
          if (_controller.previewError != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_controller.previewError}; press play to retry',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorBody() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.error_outline, size: 36),
      const SizedBox(height: 12),
      const Text('could not open this audio for cropping'),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('close'),
        ),
      ),
    ],
  );

  Widget _timeField(
    TextEditingController controller,
    String label,
    bool start,
  ) => TextField(
    controller: controller,
    focusNode: start ? _startFocus : _endFocus,
    decoration: InputDecoration(
      labelText: label,
      hintText: '0:00.000',
      errorText: start ? _startError : _endError,
    ),
    onSubmitted: (raw) => _submitTime(raw, start),
  );

  void _submitTime(String raw, bool start) {
    final value = parseCropTimestamp(raw);
    if (value == null) {
      setState(() {
        if (start) {
          _startError = 'use m:ss.mmm';
        } else {
          _endError = 'use m:ss.mmm';
        }
      });
      return;
    }
    setState(() {
      if (start) {
        _startError = null;
      } else {
        _endError = null;
      }
    });
    _controller.beginBoundaryEdit();
    start ? _controller.setStart(value) : _controller.setEnd(value);
    _controller.endBoundaryEdit();
    FocusManager.instance.primaryFocus?.unfocus();
    _start.text = formatCropTimestamp(_controller.start);
    _end.text = formatCropTimestamp(_controller.end);
  }
}

class AudioCropTimeline extends StatefulWidget {
  const AudioCropTimeline({
    super.key,
    required this.waveformPath,
    required this.duration,
    required this.start,
    required this.end,
    required this.position,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  final String? waveformPath;
  final Duration duration;
  final Duration start;
  final Duration end;
  final Duration position;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<Duration> onStartChanged;
  final ValueChanged<Duration> onEndChanged;

  @override
  State<AudioCropTimeline> createState() => _AudioCropTimelineState();
}

class _AudioCropTimelineState extends State<AudioCropTimeline> {
  static const _handleWidth = 44.0;
  double? _dragMilliseconds;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (widget.waveformPath != null)
              Image.file(File(widget.waveformPath!), fit: BoxFit.fill)
            else
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            CustomPaint(
              painter: _CropOverlayPainter(
                start: _fraction(widget.start),
                end: _fraction(widget.end),
                position: _fraction(widget.position),
              ),
            ),
            _handle(width: width, startHandle: true),
            _handle(width: width, startHandle: false),
          ],
        );
      },
    ),
  );

  double _fraction(Duration value) {
    final duration = widget.duration.inMilliseconds;
    if (duration <= 0) return 0;
    return (value.inMilliseconds / duration).clamp(0, 1);
  }

  Widget _handle({required double width, required bool startHandle}) {
    final boundary = startHandle ? widget.start : widget.end;
    final center = _fraction(boundary) * width;
    final handleWidth = width.clamp(0, _handleWidth).toDouble();
    final left = (center - handleWidth / 2)
        .clamp(0, width - handleWidth)
        .toDouble();
    final label = startHandle ? 'crop start' : 'crop end';
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: handleWidth,
      child: Semantics(
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: ValueKey('audio-crop-${startHandle ? 'start' : 'end'}-handle'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _startDrag(boundary),
            onHorizontalDragUpdate: (details) =>
                _updateDrag(details.primaryDelta ?? 0, width, startHandle),
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: _endDrag,
          ),
        ),
      ),
    );
  }

  void _startDrag(Duration boundary) {
    _dragMilliseconds = boundary.inMilliseconds.toDouble();
    widget.onInteractionStart();
  }

  void _updateDrag(double delta, double width, bool startHandle) {
    if (_dragMilliseconds == null || width <= 0) return;
    final duration = widget.duration.inMilliseconds;
    _dragMilliseconds = (_dragMilliseconds! + delta / width * duration).clamp(
      0,
      duration.toDouble(),
    );
    final value = Duration(milliseconds: _dragMilliseconds!.round());
    if (startHandle) {
      widget.onStartChanged(value);
    } else {
      widget.onEndChanged(value);
    }
  }

  void _endDrag() {
    _dragMilliseconds = null;
    widget.onInteractionEnd();
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.start,
    required this.end,
    required this.position,
  });

  final double start;
  final double end;
  final double position;

  @override
  void paint(Canvas canvas, Size size) {
    final left = start * size.width;
    final right = end * size.width;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTRB(0, 0, left, size.height), shade);
    canvas.drawRect(Rect.fromLTRB(right, 0, size.width, size.height), shade);
    final handle = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(left - 2, 0, 4, size.height), handle);
    canvas.drawRect(Rect.fromLTWH(right - 2, 0, 4, size.height), handle);
    final playhead = Paint()..color = Colors.redAccent;
    canvas.drawRect(
      Rect.fromLTWH(position * size.width - 1, 0, 2, size.height),
      playhead,
    );
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      position != oldDelegate.position;
}

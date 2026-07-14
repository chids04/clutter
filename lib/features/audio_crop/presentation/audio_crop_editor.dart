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
}) {
  final editor = AudioCropEditor(
    sourcePath: sourcePath,
    service: service,
    onPreviewStarted: onPreviewStarted,
    initialStart: initialStart,
    initialEnd: initialEnd,
  );
  if (MediaQuery.sizeOf(context).width < 700) {
    return Navigator.of(context).push<AudioCropSelection>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => editor),
    );
  }
  return showDialog<AudioCropSelection>(
    context: context,
    builder: (_) => editor,
  );
}

class AudioCropEditor extends StatefulWidget {
  const AudioCropEditor({
    super.key,
    required this.sourcePath,
    required this.service,
    required this.onPreviewStarted,
    this.initialStart,
    this.initialEnd,
  });

  final String sourcePath;
  final AudioCropService service;
  final VoidCallback onPreviewStarted;
  final Duration? initialStart;
  final Duration? initialEnd;

  @override
  State<AudioCropEditor> createState() => _AudioCropEditorState();
}

class _AudioCropEditorState extends State<AudioCropEditor> {
  late final AudioCropController _controller = AudioCropController(
    sourcePath: widget.sourcePath,
    service: widget.service,
    preview: AudioplayersCropPreview(),
    onPreviewStarted: widget.onPreviewStarted,
    initialStart: widget.initialStart,
    initialEnd: widget.initialEnd,
  );
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
    _controller.dispose();
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
                onPressed: _controller.togglePreview,
                icon: Icon(
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

  Future<void> _submitTime(String raw, bool start) async {
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
    if (start) {
      await _controller.setStart(value);
    } else {
      await _controller.setEnd(value);
    }
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
    required this.onStartChanged,
    required this.onEndChanged,
  });

  final String? waveformPath;
  final Duration duration;
  final Duration start;
  final Duration end;
  final Duration position;
  final ValueChanged<Duration> onStartChanged;
  final ValueChanged<Duration> onEndChanged;

  @override
  State<AudioCropTimeline> createState() => _AudioCropTimelineState();
}

class _AudioCropTimelineState extends State<AudioCropTimeline> {
  bool _dragStart = true;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) =>
              _chooseHandle(details.localPosition.dx, width),
          onPanUpdate: (details) => _drag(details.localPosition.dx, width),
          child: Stack(
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
            ],
          ),
        );
      },
    ),
  );

  double _fraction(Duration value) =>
      (value.inMilliseconds / widget.duration.inMilliseconds).clamp(0, 1);

  void _chooseHandle(double x, double width) {
    final fraction = (x / width).clamp(0, 1);
    _dragStart =
        (fraction - _fraction(widget.start)).abs() <=
        (fraction - _fraction(widget.end)).abs();
    _drag(x, width);
  }

  void _drag(double x, double width) {
    final fraction = (x / width).clamp(0, 1);
    final value = Duration(
      milliseconds: (widget.duration.inMilliseconds * fraction).round(),
    );
    if (_dragStart) {
      widget.onStartChanged(value);
    } else {
      widget.onEndChanged(value);
    }
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

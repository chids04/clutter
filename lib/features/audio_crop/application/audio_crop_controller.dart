import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';

class AudioCropController extends ChangeNotifier {
  AudioCropController({
    required this.sourcePath,
    required this.service,
    required this.preview,
    required this.onPreviewStarted,
    this.initialStart,
    this.initialEnd,
  });

  final String sourcePath;
  final AudioCropService service;
  final CropPreviewPlayer preview;
  final VoidCallback onPreviewStarted;
  final Duration? initialStart;
  final Duration? initialEnd;

  StreamSubscription<Duration>? _positionSubscription;
  AudioCropInfo? _info;
  Duration _start = Duration.zero;
  Duration _end = Duration.zero;
  Duration _position = Duration.zero;
  Object? _error;
  bool _loading = true;
  bool _playing = false;
  bool _previewClaimed = false;

  AudioCropInfo? get info => _info;
  Duration get start => _start;
  Duration get end => _end;
  Duration get position => _position;
  Object? get error => _error;
  bool get loading => _loading;
  bool get playing => _playing;

  AudioCropSelection? get selection => _info == null
      ? null
      : AudioCropSelection(
          start: _start,
          end: _end,
          sourceDuration: _info!.duration,
        );

  Future<void> initialize() async {
    _positionSubscription = preview.positionStream.listen(_readPosition);
    try {
      _info = await service.inspect(sourcePath);
      _start = _clamp(initialStart ?? Duration.zero);
      _end = _clamp(initialEnd ?? _info!.duration);
      if (_end - _start < const Duration(milliseconds: 100)) {
        _start = Duration.zero;
        _end = _info!.duration;
      }
      _position = _start;
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setStart(Duration value) async {
    final maximum = _end - const Duration(milliseconds: 100);
    _start = _clamp(value) > maximum ? maximum : _clamp(value);
    await _pauseForBoundaryChange();
  }

  Future<void> setEnd(Duration value) async {
    final minimum = _start + const Duration(milliseconds: 100);
    _end = _clamp(value) < minimum ? minimum : _clamp(value);
    await _pauseForBoundaryChange();
  }

  Future<void> reset() async {
    final duration = _info?.duration;
    if (duration == null) return;
    _start = Duration.zero;
    _end = duration;
    await _pauseForBoundaryChange();
  }

  Future<void> togglePreview() async {
    if (_playing) {
      await preview.pause();
      _playing = false;
      notifyListeners();
      return;
    }
    if (!_previewClaimed) {
      _previewClaimed = true;
      onPreviewStarted();
    }
    final startAt = _position < _start || _position >= _end
        ? _start
        : _position;
    _position = startAt;
    await preview.play(sourcePath, startAt);
    _playing = true;
    notifyListeners();
  }

  Future<void> _pauseForBoundaryChange() async {
    if (_playing) await preview.pause();
    _playing = false;
    _position = _start;
    await preview.seek(_start);
    notifyListeners();
  }

  void _readPosition(Duration value) {
    if (value >= _end) {
      _position = _end;
      if (_playing) unawaited(_finishPreview());
    } else {
      _position = value;
      notifyListeners();
    }
  }

  Future<void> _finishPreview() async {
    await preview.pause();
    _playing = false;
    notifyListeners();
  }

  Duration _clamp(Duration value) {
    final duration = _info?.duration ?? Duration.zero;
    if (value < Duration.zero) return Duration.zero;
    if (value > duration) return duration;
    return value;
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    unawaited(preview.dispose());
    final waveform = _info?.waveformPath;
    if (waveform != null) unawaited(service.removeTemporaryFile(waveform));
    super.dispose();
  }
}

String formatCropTimestamp(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final millis = value.inMilliseconds
      .remainder(1000)
      .toString()
      .padLeft(3, '0');
  return hours > 0
      ? '$hours:$minutes:$seconds.$millis'
      : '${value.inMinutes}:$seconds.$millis';
}

Duration? parseCropTimestamp(String raw) {
  final parts = raw.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final seconds = double.tryParse(parts.last);
  final minutes = int.tryParse(parts[parts.length - 2]);
  final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
  if (seconds == null || minutes == null || hours == null) return null;
  if (seconds < 0 || seconds >= 60 || minutes < 0 || minutes >= 60) return null;
  return Duration(
    milliseconds: ((hours * 3600 + minutes * 60 + seconds) * 1000).round(),
  );
}

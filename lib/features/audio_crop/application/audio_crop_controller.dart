import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';
import 'package:clutter/shared/services/log.dart';

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
  Future<void>? _initialization;
  Future<void>? _closingTask;
  Future<void> _playerQueue = Future.value();
  AudioCropInfo? _info;
  Duration _start = Duration.zero;
  Duration _end = Duration.zero;
  Duration _position = Duration.zero;
  Object? _error;
  String? _previewError;
  bool _loading = true;
  bool _playing = false;
  bool _previewBusy = false;
  bool _previewClaimed = false;
  bool _boundaryEditing = false;
  bool _closing = false;
  int _previewGeneration = 0;

  AudioCropInfo? get info => _info;
  Duration get start => _start;
  Duration get end => _end;
  Duration get position => _position;
  Object? get error => _error;
  String? get previewError => _previewError;
  bool get loading => _loading;
  bool get playing => _playing;
  bool get previewBusy => _previewBusy;

  AudioCropSelection? get selection => _info == null
      ? null
      : AudioCropSelection(
          start: _start,
          end: _end,
          sourceDuration: _info!.duration,
        );

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _positionSubscription = preview.positionStream.listen(_readPosition);
    AudioCropInfo? inspected;
    try {
      inspected = await service.inspect(sourcePath);
      if (_closing) return;
      _info = inspected;
      _start = _clamp(initialStart ?? Duration.zero);
      _end = _clamp(initialEnd ?? inspected.duration);
      _repairInitialSelection();
      _position = _start;
    } catch (error, stackTrace) {
      if (!_closing) _error = error;
      Log.e('audio crop inspection failed', error, stackTrace);
    } finally {
      if (_closing && inspected?.waveformPath != null) {
        await _removeWaveform(inspected!.waveformPath!);
      }
      if (!_closing) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _repairInitialSelection() {
    if (_end - _start >= const Duration(milliseconds: 100)) return;
    _start = Duration.zero;
    _end = _info!.duration;
  }

  void beginBoundaryEdit() {
    if (_closing || _boundaryEditing) return;
    _boundaryEditing = true;
    _previewGeneration++;
    final shouldPause = _playing || _previewBusy;
    _playing = false;
    _position = _start;
    _notifyIfOpen();
    if (shouldPause) unawaited(_pauseForBoundaryEdit());
  }

  void setStart(Duration value) {
    if (_closing || _info == null) return;
    final maximum = _end - const Duration(milliseconds: 100);
    final clamped = _clamp(value);
    _start = clamped > maximum ? maximum : clamped;
    _position = _start;
    _notifyIfOpen();
  }

  void setEnd(Duration value) {
    if (_closing || _info == null) return;
    final minimum = _start + const Duration(milliseconds: 100);
    final clamped = _clamp(value);
    _end = clamped < minimum ? minimum : clamped;
    _position = _start;
    _notifyIfOpen();
  }

  void endBoundaryEdit() => _boundaryEditing = false;

  void reset() {
    final duration = _info?.duration;
    if (duration == null || _closing) return;
    beginBoundaryEdit();
    _start = Duration.zero;
    _end = duration;
    _position = Duration.zero;
    endBoundaryEdit();
    _notifyIfOpen();
  }

  Future<void> togglePreview() async {
    if (_closing || _info == null || _previewBusy) return;
    _previewBusy = true;
    _previewError = null;
    _notifyIfOpen();
    if (_playing) {
      _previewGeneration++;
      _playing = false;
      await _runPlayerOperation(preview.pause, 'could not pause preview');
    } else {
      final generation = ++_previewGeneration;
      await _startPreview(generation);
    }
    _previewBusy = false;
    _notifyIfOpen();
  }

  Future<void> _startPreview(int generation) async {
    if (!_previewClaimed) {
      _previewClaimed = true;
      onPreviewStarted();
    }
    final startAt = _position < _start || _position >= _end
        ? _start
        : _position;
    _position = startAt;
    final succeeded = await _runPlayerOperation(
      () => preview.play(sourcePath, startAt),
      'could not play preview',
    );
    if (!_closing && succeeded && generation == _previewGeneration) {
      _playing = true;
    }
  }

  Future<void> _pauseForBoundaryEdit() async {
    await _runPlayerOperation(preview.pause, 'could not pause preview');
  }

  Future<bool> _runPlayerOperation(
    Future<void> Function() operation,
    String message,
  ) {
    final completion = Completer<bool>();
    _playerQueue = _playerQueue.then((_) async {
      if (_closing) {
        completion.complete(false);
        return;
      }
      try {
        await operation();
        completion.complete(true);
      } catch (error, stackTrace) {
        _previewError = message;
        Log.e(message, error, stackTrace);
        completion.complete(false);
        _notifyIfOpen();
      }
    });
    return completion.future;
  }

  void _readPosition(Duration value) {
    if (_closing || !_playing || _boundaryEditing) return;
    if (value < _end) {
      _position = value;
      _notifyIfOpen();
      return;
    }
    _position = _end;
    _playing = false;
    _notifyIfOpen();
    unawaited(_runPlayerOperation(preview.pause, 'could not pause preview'));
  }

  Duration _clamp(Duration value) {
    final duration = _info?.duration ?? Duration.zero;
    if (value < Duration.zero) return Duration.zero;
    if (value > duration) return duration;
    return value;
  }

  void _notifyIfOpen() {
    if (!_closing) notifyListeners();
  }

  Future<void> close() => _closingTask ??= _close();

  Future<void> _close() async {
    _closing = true;
    _previewGeneration++;
    await _awaitSafely(_initialization, 'finish audio crop inspection');
    await _awaitSafely(_playerQueue, 'finish preview operation');
    await _awaitSafely(
      _positionSubscription?.cancel(),
      'cancel preview position subscription',
    );
    await _awaitSafely(preview.dispose(), 'dispose crop preview');
    final waveform = _info?.waveformPath;
    if (waveform != null) await _removeWaveform(waveform);
  }

  Future<void> _removeWaveform(String path) async {
    await _awaitSafely(
      service.removeTemporaryFile(path),
      'remove crop waveform',
    );
  }

  Future<void> _awaitSafely(Future<void>? future, String message) async {
    if (future == null) return;
    try {
      await future;
    } catch (error, stackTrace) {
      Log.e(message, error, stackTrace);
    }
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

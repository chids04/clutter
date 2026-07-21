import 'package:flutter/foundation.dart';

class AudioCropInfo {
  final Duration duration;
  final String? waveformPath;

  const AudioCropInfo({required this.duration, this.waveformPath});
}

class AudioCropSelection {
  final Duration start;
  final Duration end;
  final Duration sourceDuration;

  const AudioCropSelection({
    required this.start,
    required this.end,
    required this.sourceDuration,
  });

  Duration get length => end - start;

  bool get isFullRange =>
      start <= const Duration(milliseconds: 20) &&
      (sourceDuration - end).abs() <= const Duration(milliseconds: 20);
}

abstract interface class AudioCropService {
  Future<AudioCropInfo> inspect(String sourcePath);

  Future<String> crop({
    required String sourcePath,
    required AudioCropSelection selection,
    required ValueChanged<double> onProgress,
  });

  Future<void> cancel();
  Future<void> removeTemporaryFile(String path);
}

abstract interface class CropPreviewPlayer {
  Stream<Duration> get positionStream;
  Future<void> play(String sourcePath, Duration position);
  Future<void> pause();
  Future<void> dispose();
}

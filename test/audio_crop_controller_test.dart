import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/audio_crop/application/audio_crop_controller.dart';
import 'package:clutter/features/audio_crop/data/ffmpeg_audio_crop_service.dart';
import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';

void main() {
  test('crop boundaries stay in range and at least 100ms apart', () async {
    final preview = FakeCropPreview();
    final controller = AudioCropController(
      sourcePath: '/music/song.mp3',
      service: FakeCropService(),
      preview: preview,
      onPreviewStarted: () {},
    );
    await controller.initialize();

    await controller.setEnd(const Duration(milliseconds: 50));
    expect(controller.end, const Duration(milliseconds: 100));
    await controller.setStart(const Duration(seconds: 20));
    expect(controller.start, Duration.zero);

    controller.dispose();
  });

  test('preview pauses library playback and stops at crop end', () async {
    final preview = FakeCropPreview();
    var libraryPauses = 0;
    final controller = AudioCropController(
      sourcePath: '/music/song.mp3',
      service: FakeCropService(),
      preview: preview,
      onPreviewStarted: () => libraryPauses++,
      initialStart: const Duration(seconds: 1),
      initialEnd: const Duration(seconds: 2),
    );
    await controller.initialize();

    await controller.togglePreview();
    preview.positions.add(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);

    expect(libraryPauses, 1);
    expect(preview.playedAt, const Duration(seconds: 1));
    expect(preview.pauses, 1);
    expect(controller.playing, isFalse);
    controller.dispose();
  });

  test('timestamp parser accepts minute and hour forms', () {
    expect(
      parseCropTimestamp('2:03.250'),
      const Duration(minutes: 2, seconds: 3, milliseconds: 250),
    );
    expect(
      parseCropTimestamp('1:02:03.500'),
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
    );
    expect(parseCropTimestamp('not a time'), isNull);
  });

  test('crop ffmpeg arguments encode only the selected audio as mp3', () {
    const selection = AudioCropSelection(
      start: Duration(milliseconds: 1250),
      end: Duration(milliseconds: 4750),
      sourceDuration: Duration(seconds: 10),
    );
    final arguments = buildAudioCropArguments(
      '/tmp/in.flac',
      '/tmp/out.mp3',
      selection,
    );

    expect(
      arguments,
      containsAllInOrder(['-ss', '1.250', '-i', '/tmp/in.flac']),
    );
    expect(arguments, containsAllInOrder(['-t', '3.500']));
    expect(arguments, containsAllInOrder(['-c:a', 'libmp3lame', '-q:a', '2']));
  });

  test('waveform uses the built-in bmp encoder', () {
    final arguments = buildWaveformArguments(
      '/tmp/input.mp3',
      '/tmp/waveform.bmp',
    );

    expect(arguments, containsAllInOrder(['-frames:v', '1', '-c:v', 'bmp']));
  });

  test('full range selection does not request a crop', () {
    const selection = AudioCropSelection(
      start: Duration.zero,
      end: Duration(seconds: 10),
      sourceDuration: Duration(seconds: 10),
    );

    expect(selection.isFullRange, isTrue);
  });
}

class FakeCropService implements AudioCropService {
  @override
  Future<AudioCropInfo> inspect(String sourcePath) async =>
      const AudioCropInfo(duration: Duration(seconds: 10));

  @override
  Future<String> crop({
    required String sourcePath,
    required AudioCropSelection selection,
    required ValueChanged<double> onProgress,
  }) async => '/tmp/crop.mp3';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> removeTemporaryFile(String path) async {}
}

class FakeCropPreview implements CropPreviewPlayer {
  final positions = StreamController<Duration>.broadcast();
  Duration? playedAt;
  int pauses = 0;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Future<void> play(String sourcePath, Duration position) async {
    playedAt = position;
  }

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() => positions.close();
}

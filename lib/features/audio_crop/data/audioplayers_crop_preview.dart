import 'package:audioplayers/audioplayers.dart';

import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';

class AudioplayersCropPreview implements CropPreviewPlayer {
  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  @override
  Stream<Duration> get positionStream => _player.onPositionChanged;

  @override
  Future<void> play(String sourcePath, Duration position) =>
      _player.play(DeviceFileSource(sourcePath), position: position);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() => _player.dispose();
}

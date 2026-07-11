import 'package:audio_service/audio_service.dart';

import 'package:clutter/features/library/domain/library_entities.dart';

// this keeps queue policy independent from the platform audio implementation
abstract interface class AudioPlayerPort {
  Stream<PlaybackState> get playbackStateStream;
  Stream<MediaItem?> get mediaItemStream;
  Stream<Duration> get positionStream;

  Future<void> Function()? get onSkipToNext;
  set onSkipToNext(Future<void> Function()? callback);
  Future<void> Function()? get onSkipToPrevious;
  set onSkipToPrevious(Future<void> Function()? callback);
  Future<void> Function()? get onTrackComplete;
  set onTrackComplete(Future<void> Function()? callback);

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> loadAndPlay(SongViewData song, {Duration? startPosition});
  Future<void> setVolume(double volume);
  Future<void> setLoopOne(bool loopOne);
}

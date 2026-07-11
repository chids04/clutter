import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/application/playback_controller.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';

SongViewData testSong(String id) => SongViewData(
  id: id,
  title: 'song $id',
  primaryArtist: 'artist',
  featuredArtists: const [],
  filePath: '/music/$id.mp3',
  trackNum: 1,
  discNum: 1,
  album: 'album',
  albumId: 'album-id',
  albumArtists: const ['artist'],
);

class FakePlaybackPersistence implements PlaybackPersistence {
  PlaybackStateData? saved;

  @override
  Future<PlaybackStateData?> loadPlaybackState() async => saved;

  @override
  Future<List<SongViewData>> getRecentlyPlayed(int limit) async => const [];

  @override
  Future<void> recordPlay(String songId) async {}

  @override
  Future<void> savePlaybackState(
    String? songId,
    int positionMs,
    bool loopOne,
  ) async {}
}

class FakeAudioPlayer implements AudioPlayerPort {
  @override
  Stream<PlaybackState> get playbackStateStream => const Stream.empty();
  @override
  Stream<MediaItem?> get mediaItemStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Future<void> Function()? onSkipToNext;
  @override
  Future<void> Function()? onSkipToPrevious;
  @override
  Future<void> Function()? onTrackComplete;

  @override
  Future<void> loadAndPlay(
    SongViewData song, {
    Duration? startPosition,
  }) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setLoopOne(bool loopOne) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
}

void main() {
  test('hydrate restores state without starting platform playback', () async {
    final persistence = FakePlaybackPersistence()
      ..saved = PlaybackStateData(
        song: testSong('saved'),
        positionMs: 4200,
        loopOne: true,
      );
    final controller = PlaybackController(
      persistence: persistence,
      player: FakeAudioPlayer(),
    );

    await controller.hydrate();

    expect(controller.currentSong?.id, 'saved');
    expect(controller.position, const Duration(milliseconds: 4200));
    expect(controller.loopOne, isTrue);
    expect(controller.isPlaying, isFalse);
    controller.dispose();
  });
}

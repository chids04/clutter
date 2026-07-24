import 'dart:async';

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
  final List<SongViewData> loaded = [];
  final List<Duration> seeks = [];
  final StreamController<MediaItem?> mediaItems =
      StreamController<MediaItem?>.broadcast();
  int playCalls = 0;

  @override
  Stream<PlaybackState> get playbackStateStream => const Stream.empty();
  @override
  Stream<MediaItem?> get mediaItemStream => mediaItems.stream;
  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Future<void> Function()? onSkipToNext;
  @override
  Future<void> Function()? onSkipToPrevious;
  @override
  Future<void> Function()? onTrackComplete;

  @override
  Future<void> loadAndPlay(SongViewData song, {Duration? startPosition}) async {
    loaded.add(song);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

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
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      persistence: persistence,
      player: player,
    );

    await controller.hydrate();

    expect(controller.currentSong?.id, 'saved');
    expect(controller.position, const Duration(milliseconds: 4200));
    expect(controller.loopOne, isTrue);
    expect(controller.isPlaying, isFalse);
    expect(player.loaded, isEmpty);
    controller.dispose();
  });

  test('playSongById loads a new song', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: player,
    );
    final songs = [testSong('a'), testSong('b')];

    await controller.playSongById('a', songs);

    expect(controller.currentSong?.id, 'a');
    expect(controller.isPlaying, isTrue);
    expect(controller.position, Duration.zero);
    expect(player.loaded.map((s) => s.id), ['a']);
    controller.dispose();
  });

  test('playSongById restarts the current song from the beginning', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: player,
    );
    final songs = [testSong('a'), testSong('b')];

    await controller.playSongById('a', songs);
    player.loaded.clear();

    await controller.playSongById('a', songs);

    expect(controller.currentSong?.id, 'a');
    expect(controller.isPlaying, isTrue);
    expect(controller.position, Duration.zero);
    expect(player.seeks, [Duration.zero]);
    expect(player.loaded, isEmpty);
    expect(controller.queue, isEmpty);
    controller.dispose();
  });

  test('playSongById restarts and resumes when paused', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: player,
    );
    final songs = [testSong('a')];

    await controller.playSongById('a', songs);
    await controller.pause();
    player.loaded.clear();
    player.seeks.clear();
    player.playCalls = 0;

    await controller.playSongById('a', songs);

    expect(controller.isPlaying, isTrue);
    expect(controller.position, Duration.zero);
    expect(player.seeks, [Duration.zero]);
    expect(player.playCalls, 1);
    expect(player.loaded, isEmpty);
    controller.dispose();
  });

  test('playSongById reloads when source is not loaded yet', () async {
    final persistence = FakePlaybackPersistence()
      ..saved = PlaybackStateData(
        song: testSong('saved'),
        positionMs: 4200,
        loopOne: false,
      );
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      persistence: persistence,
      player: player,
    );
    final songs = [testSong('saved')];

    await controller.hydrate();
    await controller.playSongById('saved', songs);

    expect(controller.currentSong?.id, 'saved');
    expect(controller.isPlaying, isTrue);
    expect(controller.position, Duration.zero);
    expect(player.loaded.map((s) => s.id), ['saved']);
    expect(player.seeks, isEmpty);
    controller.dispose();
  });

  test(
    'seekBy clamps to the song bounds without changing play state',
    () async {
      final player = FakeAudioPlayer();
      final controller = PlaybackController(
        persistence: FakePlaybackPersistence(),
        player: player,
      );
      await controller.playSongById('a', [testSong('a')]);
      player.mediaItems.add(
        const MediaItem(
          id: 'a',
          title: 'song a',
          duration: Duration(seconds: 10),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.seekBy(const Duration(seconds: 7));
      await controller.seekBy(const Duration(seconds: 7));
      await controller.seekBy(const Duration(seconds: -20));

      expect(player.seeks, const [
        Duration(seconds: 7),
        Duration(seconds: 10),
        Duration.zero,
      ]);
      expect(controller.position, Duration.zero);
      expect(controller.isPlaying, isTrue);
      controller.dispose();
    },
  );

  test('seekBy preserves paused state', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: player,
    );
    await controller.playSongById('a', [testSong('a')]);
    await controller.pause();

    await controller.seekBy(const Duration(seconds: 5));

    expect(player.seeks, const [Duration(seconds: 5)]);
    expect(controller.isPlaying, isFalse);
    controller.dispose();
  });

  test(
    'seekBy updates an unloaded saved position without touching player',
    () async {
      final persistence = FakePlaybackPersistence()
        ..saved = PlaybackStateData(
          song: testSong('saved'),
          positionMs: 4200,
          loopOne: false,
        );
      final player = FakeAudioPlayer();
      final controller = PlaybackController(
        persistence: persistence,
        player: player,
      );
      await controller.hydrate();

      await controller.seekBy(const Duration(seconds: 5));

      expect(controller.position, const Duration(milliseconds: 9200));
      expect(player.seeks, isEmpty);
      controller.dispose();
    },
  );

  test('seekBy does nothing without a current song', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: player,
    );

    await controller.seekBy(const Duration(seconds: 5));

    expect(player.seeks, isEmpty);
    controller.dispose();
  });
}

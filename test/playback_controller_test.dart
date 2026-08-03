import 'dart:async';
import 'dart:math';

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
  final StreamController<PlaybackState> playbackStates =
      StreamController<PlaybackState>.broadcast(sync: true);
  int playCalls = 0;
  bool startSucceeds = true;

  @override
  Stream<PlaybackState> get playbackStateStream => playbackStates.stream;
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
    _emitPlaybackState(startSucceeds);
  }

  @override
  Future<void> pause() async {
    _emitPlaybackState(false);
  }

  @override
  Future<void> play() async {
    playCalls++;
    _emitPlaybackState(startSucceeds);
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
  Future<void> stop() async {
    _emitPlaybackState(false);
  }

  void _emitPlaybackState(bool playing) {
    playbackStates.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: playing,
      ),
    );
  }
}

class IdentityShuffleRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => max - 1;
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

  test('a denied playback start does not publish optimistic playing', () async {
    final player = FakeAudioPlayer()..startSucceeds = false;
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: player,
    );

    await controller.playSongById('a', [testSong('a')]);

    expect(controller.currentSong?.id, 'a');
    expect(controller.isPlaying, isFalse);
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

  test('previous restarts the current song after the threshold', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: player,
    );
    await controller.playSongById('a', [testSong('a')]);
    controller.setPosition(4000);

    await controller.playPrevious();

    expect(controller.currentSong?.id, 'a');
    expect(controller.position, Duration.zero);
    expect(player.seeks, [Duration.zero]);
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

  test('shuffleQueue changes the order on every press', () {
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: FakeAudioPlayer(),
    );
    final songs = [testSong('a'), testSong('b'), testSong('c'), testSong('d')];
    controller.addAllToQueue(songs);
    var changes = 0;
    controller.addListener(() => changes++);

    final original = controller.queue.map((song) => song.id).toList();
    controller.shuffleQueue(random: IdentityShuffleRandom());
    final firstShuffle = controller.queue.map((song) => song.id).toList();
    controller.shuffleQueue(random: IdentityShuffleRandom());
    final secondShuffle = controller.queue.map((song) => song.id).toList();

    expect(firstShuffle, isNot(equals(original)));
    expect(secondShuffle, isNot(equals(firstShuffle)));
    expect(secondShuffle, unorderedEquals(original));
    expect(changes, 2);
    controller.dispose();
  });

  test('shuffleQueue does nothing with fewer than two songs', () {
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: FakeAudioPlayer(),
    );
    var changes = 0;
    controller.addListener(() => changes++);

    controller.shuffleQueue(random: IdentityShuffleRandom());
    expect(changes, 0);

    controller.addToQueue(testSong('a'));
    changes = 0;
    controller.shuffleQueue(random: IdentityShuffleRandom());

    expect(controller.queue.map((song) => song.id), ['a']);
    expect(changes, 0);
    controller.dispose();
  });

  test('shuffleQueue refreshes the loop queue snapshot', () async {
    final controller = PlaybackController(
      persistence: FakePlaybackPersistence(),
      player: FakeAudioPlayer(),
    );
    await controller.playSongById('current', [testSong('current')]);
    controller.addAllToQueue([testSong('a'), testSong('b'), testSong('c')]);
    controller.toggleLoopQueue();

    controller.shuffleQueue(random: IdentityShuffleRandom());

    expect(controller.queueState.restartLoop().map((song) => song.id), [
      'current',
      ...controller.queue.map((song) => song.id),
    ]);
    controller.dispose();
  });
}

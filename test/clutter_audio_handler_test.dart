import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/infrastructure/audio_session_port.dart';
import 'package:clutter/features/playback/infrastructure/clutter_audio_handler.dart';

const _song = SongViewData(
  id: 'song-id',
  title: 'song',
  primaryArtist: 'artist',
  featuredArtists: [],
  filePath: '/music/song.mp3',
  trackNum: 1,
  discNum: 1,
  album: 'album',
  albumId: 'album-id',
  albumArtists: ['artist'],
);

const _otherSong = SongViewData(
  id: 'other-song-id',
  title: 'other song',
  primaryArtist: 'artist',
  featuredArtists: [],
  filePath: '/music/other-song.mp3',
  trackNum: 2,
  discNum: 1,
  album: 'album',
  albumId: 'album-id',
  albumArtists: ['artist'],
);

class _FakeAudioSession implements PlaybackAudioSession {
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast();
  final noisyEvents = StreamController<void>.broadcast();
  final List<bool> activations = [];
  final activationResults = <bool>[];
  Completer<bool>? activationGate;
  int configureCalls = 0;

  @override
  Stream<void> get becomingNoisyEvents => noisyEvents.stream;

  @override
  Stream<AudioInterruptionEvent> get interruptionEvents => interruptions.stream;

  @override
  Future<void> configureMusic() async {
    configureCalls++;
  }

  @override
  Future<bool> setActive(bool active) async {
    activations.add(active);
    if (activationGate case final gate?) return gate.future;
    return activationResults.isEmpty ? true : activationResults.removeAt(0);
  }

  Future<void> emitInterruption(bool begin, AudioInterruptionType type) async {
    interruptions.add(AudioInterruptionEvent(begin, type));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    await interruptions.close();
    await noisyEvents.close();
  }
}

class _FakeAudioEngine implements PlaybackAudioEngine {
  final states = StreamController<PlayerState>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final completed = StreamController<void>.broadcast();

  @override
  PlayerState state = PlayerState.stopped;
  @override
  double playbackRate = 1;
  int playCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  final List<Source> sources = [];
  final seeks = <Duration>[];
  Completer<void>? pauseGate;
  Completer<void>? seekGate;

  @override
  Stream<void> get completions => completed.stream;
  @override
  Stream<Duration> get durationChanges => durations.stream;
  @override
  Stream<PlayerState> get playerStateChanges => states.stream;
  @override
  Stream<Duration> get positionChanges => positions.stream;

  @override
  Future<void> pause() async {
    pauseCalls++;
    await pauseGate?.future;
    state = PlayerState.paused;
    states.add(state);
  }

  @override
  Future<void> setSource(Source source) async {
    playCalls++;
    sources.add(source);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    state = PlayerState.playing;
    states.add(state);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    await seekGate?.future;
  }

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}
  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {
    state = PlayerState.stopped;
    states.add(state);
  }

  Future<void> close() async {
    await states.close();
    await durations.close();
    await positions.close();
    await completed.close();
  }
}

void main() {
  test('resumes playback after a resumable interruption', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);

    await session.emitInterruption(true, AudioInterruptionType.pause);
    expect(engine.pauseCalls, 1);
    expect(handler.mediaItem.value?.id, _song.id);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );

    await session.emitInterruption(false, AudioInterruptionType.pause);
    expect(engine.resumeCalls, 2);
    expect(handler.playbackState.value.playing, isTrue);
    expect(session.activations, [true, true]);

    await session.close();
    await engine.close();
  });

  test('finishes interruption pause before resuming playback', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine()..pauseGate = Completer<void>();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);

    await session.emitInterruption(true, AudioInterruptionType.unknown);
    await session.emitInterruption(false, AudioInterruptionType.pause);

    expect(engine.pauseCalls, 1);
    expect(engine.resumeCalls, 1);

    engine.pauseGate!.complete();
    await Future<void>.delayed(Duration.zero);

    expect(engine.resumeCalls, 2);
    expect(engine.state, PlayerState.playing);
    expect(handler.playbackState.value.playing, isTrue);

    await session.close();
    await engine.close();
  });

  test(
    'a user pause during interruption suppresses automatic resume',
    () async {
      final session = _FakeAudioSession();
      final engine = _FakeAudioEngine()..pauseGate = Completer<void>();
      final handler = ClutterAudioHandler(session: session, player: engine);
      await handler.initialize();
      await handler.loadAndPlay(_song);

      await session.emitInterruption(true, AudioInterruptionType.unknown);
      final userPause = handler.pause();
      await session.emitInterruption(false, AudioInterruptionType.pause);
      engine.pauseGate!.complete();
      await userPause;
      await Future<void>.delayed(Duration.zero);

      expect(engine.resumeCalls, 1);
      expect(handler.playbackState.value.playing, isFalse);

      await session.close();
      await engine.close();
    },
  );

  test('remote play reactivates after a non-resumable interruption', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);

    await session.emitInterruption(true, AudioInterruptionType.unknown);
    await session.emitInterruption(false, AudioInterruptionType.unknown);
    expect(engine.resumeCalls, 1);
    expect(handler.mediaItem.value?.id, _song.id);

    await handler.play();
    expect(engine.resumeCalls, 2);
    expect(handler.playbackState.value.playing, isTrue);

    await session.close();
    await engine.close();
  });

  test('manual play reclaims a session without an interruption end', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);

    await session.emitInterruption(true, AudioInterruptionType.unknown);
    await handler.play();

    expect(session.activations, [true, true]);
    expect(engine.resumeCalls, 2);
    expect(handler.playbackState.value.playing, isTrue);

    await session.close();
    await engine.close();
  });

  test('selecting another song reclaims and prepares the new source', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);

    await session.emitInterruption(true, AudioInterruptionType.unknown);
    await handler.loadAndPlay(_otherSong);

    expect(session.activations, [true, true]);
    expect(engine.sources, hasLength(2));
    expect((engine.sources.last as DeviceFileSource).path, _otherSong.filePath);
    expect(handler.mediaItem.value?.id, _otherSong.id);
    expect(handler.playbackState.value.playing, isTrue);

    await session.close();
    await engine.close();
  });

  test('a denied new song remains prepared for a later play retry', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);
    await session.emitInterruption(true, AudioInterruptionType.unknown);
    session.activationResults.add(false);

    await handler.loadAndPlay(_otherSong);

    expect((engine.sources.last as DeviceFileSource).path, _otherSong.filePath);
    expect(handler.mediaItem.value?.id, _otherSong.id);
    expect(handler.playbackState.value.playing, isFalse);

    await handler.play();

    expect(engine.sources, hasLength(2));
    expect(engine.resumeCalls, 2);
    expect(handler.playbackState.value.playing, isTrue);

    await session.close();
    await engine.close();
  });

  test('manual play retries a denial without an interruption end', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);
    await session.emitInterruption(true, AudioInterruptionType.unknown);
    session.activationResults.add(false);

    await handler.play();
    expect(handler.playbackState.value.playing, isFalse);

    await handler.play();
    expect(session.activations, [true, true, true]);
    expect(engine.resumeCalls, 2);
    expect(handler.playbackState.value.playing, isTrue);

    await session.close();
    await engine.close();
  });

  test('a delayed interruption end is ignored after manual reclaim', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);
    await session.emitInterruption(true, AudioInterruptionType.unknown);
    await handler.play();

    await session.emitInterruption(false, AudioInterruptionType.pause);

    expect(session.activations, [true, true]);
    expect(engine.resumeCalls, 2);
    expect(handler.playbackState.value.playing, isTrue);

    await session.close();
    await engine.close();
  });

  test(
    'a denied reactivation remains paused and manual play retries',
    () async {
      final session = _FakeAudioSession();
      final engine = _FakeAudioEngine();
      final handler = ClutterAudioHandler(session: session, player: engine);
      await handler.initialize();
      await handler.loadAndPlay(_song);
      session.activationResults.add(false);

      await session.emitInterruption(true, AudioInterruptionType.unknown);
      await session.emitInterruption(false, AudioInterruptionType.pause);

      expect(engine.resumeCalls, 1);
      expect(handler.playbackState.value.playing, isFalse);

      await handler.play();

      expect(engine.resumeCalls, 2);
      expect(handler.playbackState.value.playing, isTrue);
      expect(session.activations, [true, true, true]);

      await session.close();
      await engine.close();
    },
  );

  test('a user pause while reactivating prevents the pending resume', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);

    await session.emitInterruption(true, AudioInterruptionType.unknown);
    session.activationGate = Completer<bool>();
    await session.emitInterruption(false, AudioInterruptionType.pause);
    final userPause = handler.pause();
    session.activationGate!.complete(true);
    await userPause;
    await Future<void>.delayed(Duration.zero);

    expect(engine.resumeCalls, 1);
    expect(handler.playbackState.value.playing, isFalse);

    await session.close();
    await engine.close();
  });

  test(
    'publishes a restarted position after the engine seek completes',
    () async {
      final session = _FakeAudioSession();
      final engine = _FakeAudioEngine();
      final handler = ClutterAudioHandler(session: session, player: engine);
      await handler.initialize();
      await handler.loadAndPlay(_song);
      await handler.seek(const Duration(seconds: 12));
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 12),
      );

      engine.seekGate = Completer<void>();
      final restart = handler.seek(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 12),
      );

      engine.seekGate!.complete();
      await restart;

      expect(engine.seeks, [const Duration(seconds: 12), Duration.zero]);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      expect(handler.playbackState.value.playing, isTrue);

      await session.close();
      await engine.close();
    },
  );

  test('anchors elapsed playback before restarting at zero', () async {
    final session = _FakeAudioSession();
    final engine = _FakeAudioEngine();
    final handler = ClutterAudioHandler(session: session, player: engine);
    await handler.initialize();
    await handler.loadAndPlay(_song);
    final publishedPositions = <Duration>[];
    final subscription = handler.playbackState.listen(
      (state) => publishedPositions.add(state.updatePosition),
    );
    await Future<void>.delayed(Duration.zero);
    publishedPositions.clear();

    engine.positions.add(const Duration(seconds: 12));
    await Future<void>.delayed(Duration.zero);
    expect(handler.playbackState.value.updatePosition, Duration.zero);

    await handler.seek(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(publishedPositions, [const Duration(seconds: 12), Duration.zero]);
    expect(engine.seeks, [Duration.zero]);
    expect(handler.playbackState.value.playing, isTrue);

    await subscription.cancel();
    await session.close();
    await engine.close();
  });
}

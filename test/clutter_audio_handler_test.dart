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

class _FakeAudioSession implements PlaybackAudioSession {
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast();
  final noisyEvents = StreamController<void>.broadcast();
  final List<bool> activations = [];

  @override
  Stream<void> get becomingNoisyEvents => noisyEvents.stream;

  @override
  Stream<AudioInterruptionEvent> get interruptionEvents => interruptions.stream;

  @override
  Future<void> configureMusic() async {}

  @override
  Future<bool> setActive(bool active) async {
    activations.add(active);
    return true;
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
    state = PlayerState.paused;
    states.add(state);
  }

  @override
  Future<void> play(Source source, {Duration? position}) async {
    playCalls++;
    state = PlayerState.playing;
    states.add(state);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    state = PlayerState.playing;
    states.add(state);
  }

  @override
  Future<void> seek(Duration position) async {}
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
    expect(engine.resumeCalls, 1);
    expect(handler.playbackState.value.playing, isTrue);
    expect(session.activations, [true, true]);

    await session.close();
    await engine.close();
  });

  test(
    'a user pause during interruption suppresses automatic resume',
    () async {
      final session = _FakeAudioSession();
      final engine = _FakeAudioEngine();
      final handler = ClutterAudioHandler(session: session, player: engine);
      await handler.initialize();
      await handler.loadAndPlay(_song);

      await session.emitInterruption(true, AudioInterruptionType.pause);
      await handler.pause();
      await session.emitInterruption(false, AudioInterruptionType.pause);

      expect(engine.resumeCalls, 0);
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
    expect(engine.resumeCalls, 0);
    expect(handler.mediaItem.value?.id, _song.id);

    await handler.play();
    expect(engine.resumeCalls, 1);
    expect(handler.playbackState.value.playing, isTrue);

    await session.close();
    await engine.close();
  });
}

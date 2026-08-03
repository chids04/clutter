import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';
import 'package:clutter/features/playback/infrastructure/audio_session_port.dart';
import 'package:clutter/shared/services/log.dart';

abstract interface class PlaybackAudioEngine {
  PlayerState get state;
  double get playbackRate;
  Stream<PlayerState> get playerStateChanges;
  Stream<Duration> get durationChanges;
  Stream<Duration> get positionChanges;
  Stream<void> get completions;

  Future<void> setSource(Source source);
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setReleaseMode(ReleaseMode mode);
}

class AudioplayersEngine implements PlaybackAudioEngine {
  final AudioPlayer _player = AudioPlayer();

  @override
  PlayerState get state => _player.state;

  @override
  double get playbackRate => _player.playbackRate;

  @override
  Stream<PlayerState> get playerStateChanges => _player.onPlayerStateChanged;

  @override
  Stream<Duration> get durationChanges => _player.onDurationChanged;

  @override
  Stream<Duration> get positionChanges => _player.onPositionChanged;

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Future<void> setSource(Source source) => _player.setSource(source);

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setReleaseMode(ReleaseMode mode) {
    return _player.setReleaseMode(mode);
  }
}

/// Owns the platform player and publishes a stable system media session.
class ClutterAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements AudioPlayerPort {
  final PlaybackAudioSession session;
  final PlaybackAudioEngine _player;

  ClutterAudioHandler({required this.session, PlaybackAudioEngine? player})
    : _player = player ?? AudioplayersEngine() {
    _initPlayerListeners();
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _operationQueue = Future.value();
  Duration _position = Duration.zero;
  bool _wantsToPlay = false;
  bool _interrupted = false;
  bool _resumeAfterInterruption = false;
  bool _initialized = false;

  @override
  Stream<PlaybackState> get playbackStateStream => playbackState;

  @override
  Stream<MediaItem?> get mediaItemStream => mediaItem;

  @override
  Stream<Duration> get positionStream => AudioService.position;

  @override
  Future<void> Function()? onSkipToNext;

  @override
  Future<void> Function()? onSkipToPrevious;

  @override
  Future<void> Function()? onTrackComplete;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _player.setReleaseMode(ReleaseMode.stop);
    await session.configureMusic();
    _subscriptions.add(session.interruptionEvents.listen(_enqueueInterruption));
    _subscriptions.add(
      session.becomingNoisyEvents.listen((_) => unawaited(pause())),
    );
  }

  @override
  Future<void> play() async {
    if (mediaItem.value == null) return;
    _wantsToPlay = true;
    if (_interrupted) _resumeAfterInterruption = true;
    await _enqueueOperation(_activateAndResume);
  }

  @override
  Future<void> pause() async {
    _wantsToPlay = false;
    _resumeAfterInterruption = false;
    await _enqueueOperation(_pausePlayer);
  }

  @override
  Future<void> stop() async {
    _wantsToPlay = false;
    _resumeAfterInterruption = false;
    await _enqueueOperation(() async {
      _interrupted = false;
      await _player.stop();
      await super.stop();
      mediaItem.add(null);
      _position = Duration.zero;
      _broadcastPlaybackState(
        playingOverride: false,
        processingOverride: AudioProcessingState.idle,
      );
    });
  }

  @override
  Future<void> seek(Duration position) async {
    await _enqueueOperation(() async {
      final publishedState = playbackState.value;
      final currentPosition = _position == publishedState.updatePosition
          ? publishedState.position
          : _position;
      if (currentPosition != publishedState.updatePosition) {
        _position = currentPosition;
        _broadcastPlaybackState();
      }
      await _player.seek(position);
      _position = position;
      _broadcastPlaybackState();
    });
  }

  @override
  Future<void> skipToNext() async {
    await onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onSkipToPrevious?.call();
  }

  @override
  Future<void> loadAndPlay(SongViewData song, {Duration? startPosition}) async {
    _wantsToPlay = true;
    if (_interrupted) _resumeAfterInterruption = true;
    await _enqueueOperation(() async {
      _position = startPosition ?? Duration.zero;
      mediaItem.add(_songToMediaItem(song));
      _broadcastPlaybackState(
        playingOverride: false,
        processingOverride: AudioProcessingState.loading,
      );
      try {
        await _player.setSource(DeviceFileSource(song.filePath));
        if (startPosition != null && startPosition > Duration.zero) {
          await _player.seek(startPosition);
        }
        await _activateAndResume();
      } catch (error, stackTrace) {
        Log.e('audio source preparation failed', error, stackTrace);
        _broadcastPlaybackState(
          playingOverride: false,
          processingOverride: AudioProcessingState.ready,
        );
      }
    });
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setLoopOne(bool loopOne) {
    return _player.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> _handleInterruption(AudioInterruptionEvent event) async {
    if (event.begin) {
      _interrupted = true;
      _resumeAfterInterruption = _wantsToPlay;
      if (_wantsToPlay || _player.state == PlayerState.playing) {
        await _pausePlayer();
      }
      return;
    }

    if (!_interrupted) return;
    _interrupted = false;
    final shouldResume =
        event.type == AudioInterruptionType.pause ||
        event.type == AudioInterruptionType.duck;
    final resume = _resumeAfterInterruption && _wantsToPlay && shouldResume;
    _resumeAfterInterruption = false;
    if (resume) {
      await _activateAndResume();
    } else {
      _broadcastPlaybackState(
        playingOverride: false,
        processingOverride: mediaItem.value == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
      );
    }
  }

  Future<void> _activateAndResume() async {
    try {
      await session.configureMusic();
      final activated = await session.setActive(true);
      if (!activated || !_wantsToPlay) {
        _broadcastPlaybackState(
          playingOverride: false,
          processingOverride: AudioProcessingState.ready,
        );
        return;
      }
      _interrupted = false;
      _resumeAfterInterruption = false;
      await _player.resume();
      _broadcastPlaybackState(
        playingOverride: true,
        processingOverride: AudioProcessingState.ready,
      );
    } catch (error, stackTrace) {
      Log.e('audio session activation failed', error, stackTrace);
      _broadcastPlaybackState(
        playingOverride: false,
        processingOverride: AudioProcessingState.ready,
      );
    }
  }

  void _enqueueInterruption(AudioInterruptionEvent event) {
    unawaited(_enqueueOperation(() => _handleInterruptionSafely(event)));
  }

  Future<void> _handleInterruptionSafely(AudioInterruptionEvent event) async {
    try {
      await _handleInterruption(event);
    } catch (error, stackTrace) {
      Log.e('audio interruption recovery failed', error, stackTrace);
      _broadcastPlaybackState(
        playingOverride: false,
        processingOverride: mediaItem.value == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
      );
    }
  }

  Future<void> _pausePlayer() async {
    await _player.pause();
    _broadcastPlaybackState(
      playingOverride: false,
      processingOverride: mediaItem.value == null
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
    );
  }

  Future<void> _enqueueOperation(Future<void> Function() operation) {
    final completer = Completer<void>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  MediaItem _songToMediaItem(SongViewData song) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: _artistsDisplay(song),
      album: song.album.isEmpty ? null : song.album,
      duration: null,
      artUri: song.coverPath != null ? Uri.file(song.coverPath!) : null,
    );
  }

  String _artistsDisplay(SongViewData song) {
    if (song.featuredArtists.isEmpty) return song.primaryArtist;
    return '${song.primaryArtist} feat. ${song.featuredArtists.join(', ')}';
  }

  void _initPlayerListeners() {
    _subscriptions.add(
      _player.playerStateChanges.listen((_) {
        _broadcastPlaybackState();
      }),
    );
    _subscriptions.add(
      _player.durationChanges.listen((duration) {
        final item = mediaItem.value;
        if (item != null && duration > Duration.zero) {
          mediaItem.add(item.copyWith(duration: duration));
        }
        _broadcastPlaybackState();
      }),
    );
    _subscriptions.add(
      _player.positionChanges.listen((position) {
        _position = position;
      }),
    );
    _subscriptions.add(
      _player.completions.listen((_) async {
        _wantsToPlay = false;
        _broadcastPlaybackState(
          playingOverride: false,
          processingOverride: AudioProcessingState.completed,
        );
        await onTrackComplete?.call();
      }),
    );
  }

  void _broadcastPlaybackState({
    bool? playingOverride,
    AudioProcessingState? processingOverride,
  }) {
    final item = mediaItem.value;
    final isPlaying =
        playingOverride ??
        (!_interrupted && _player.state == PlayerState.playing);
    final processingState =
        processingOverride ?? _mapProcessingState(_player.state, item != null);
    final controls = item == null
        ? const <MediaControl>[]
        : <MediaControl>[
            MediaControl.skipToPrevious,
            if (isPlaying) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: item == null
            ? const {}
            : const {
                MediaAction.seek,
                MediaAction.seekForward,
                MediaAction.seekBackward,
              },
        androidCompactActionIndices: item == null ? null : const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: _position,
        bufferedPosition: _position,
        speed: _player.playbackRate,
        queueIndex: item != null ? 0 : null,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(PlayerState state, bool hasItem) {
    return switch (state) {
      PlayerState.stopped =>
        hasItem ? AudioProcessingState.ready : AudioProcessingState.idle,
      PlayerState.playing || PlayerState.paused => AudioProcessingState.ready,
      PlayerState.completed => AudioProcessingState.completed,
      PlayerState.disposed => AudioProcessingState.idle,
    };
  }
}

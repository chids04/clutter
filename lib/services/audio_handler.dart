import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:clutter/src/rust/api/scanner.dart';

/// Audio-service handler that owns the underlying [AudioPlayer] and exposes
/// playback through the platform media session (Control Center, lock screen,
/// menu-bar Now Playing, headset clicks, etc.).
///
/// The actual queue/history policy still lives in [MusicLibrary]; this handler
/// forwards skip requests back to the library via the [onSkipToNext] and
/// [onSkipToPrevious] callbacks.
class ClutterAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  ClutterAudioHandler() {
    _initPlayerListeners();
  }

  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  final List<StreamSubscription<void>> _subs = [];
  Duration _position = Duration.zero;
  bool _loopOne = false;

  /// Called when the user activates "next" from system media controls.
  Future<void> Function()? onSkipToNext;

  /// Called when the user activates "previous" from system media controls.
  Future<void> Function()? onSkipToPrevious;

  @override
  Future<void> play() async {
    if (mediaItem.value == null) return;
    await _player.resume();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _broadcastPlaybackState();
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onSkipToPrevious?.call();
  }

  /// Load [song] into the player and start playback. If [startPosition] is
  /// supplied, playback begins from that offset.
  Future<void> loadAndPlay(SongViewData song, {Duration? startPosition}) async {
    final item = _songToMediaItem(song);
    mediaItem.add(item);
    await _player.play(
      DeviceFileSource(song.filePath),
      position: startPosition,
    );
  }

  /// Set the player volume in the range [0.0, 1.0].
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  /// Enable or disable single-track loop. Looping is implemented manually so
  /// that position/duration streams stay alive across iterations.
  Future<void> setLoopOne(bool loopOne) async {
    _loopOne = loopOne;
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  MediaItem _songToMediaItem(SongViewData song) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: _artistsDisplay(song),
      album: song.album.isEmpty ? null : song.album,
      // Duration is not available in [SongViewData]; it is populated once the
      // player reports the real duration via [onDurationChanged].
      duration: null,
      artUri: song.coverPath != null ? Uri.file(song.coverPath!) : null,
    );
  }

  String _artistsDisplay(SongViewData song) {
    if (song.featuredArtists.isEmpty) return song.primaryArtist;
    return '${song.primaryArtist} feat. ${song.featuredArtists.join(', ')}';
  }

  void _initPlayerListeners() {
    _subs.add(
      _player.onPlayerStateChanged.listen((state) {
        _broadcastPlaybackState();
      }),
    );
    _subs.add(
      _player.onDurationChanged.listen((duration) {
        final item = mediaItem.value;
        if (item != null && duration > Duration.zero) {
          mediaItem.add(item.copyWith(duration: duration));
        }
        _broadcastPlaybackState();
      }),
    );
    _subs.add(
      _player.onPositionChanged.listen((position) {
        _position = position;
      }),
    );
    _subs.add(
      _player.onPlayerComplete.listen((_) async {
        if (_loopOne) {
          // Manually restart the track so audioplayers' position/duration
          // streams stay alive. ReleaseMode.loop can cause those streams to
          // stop firing after the first iteration.
          _position = Duration.zero;
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.ready,
              playing: true,
              updatePosition: Duration.zero,
              bufferedPosition: Duration.zero,
            ),
          );

          await _player.seek(Duration.zero);
          await _player.resume();

          return;
        }
        _broadcastPlaybackState();
        await onSkipToNext?.call();
      }),
    );
  }

  void _broadcastPlaybackState() {
    final item = mediaItem.value;
    final isPlaying = _player.state == PlayerState.playing;
    final processingState = _mapProcessingState(_player.state);

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: _position,
        bufferedPosition: _position,
        speed: _player.playbackRate,
        queueIndex: item != null ? 0 : null,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(PlayerState state) {
    return switch (state) {
      PlayerState.stopped => AudioProcessingState.idle,
      PlayerState.playing => AudioProcessingState.ready,
      PlayerState.paused => AudioProcessingState.ready,
      PlayerState.completed => AudioProcessingState.completed,
      PlayerState.disposed => AudioProcessingState.idle,
    };
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await super.onTaskRemoved();
  }
}

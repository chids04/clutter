import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';
import 'package:clutter/features/playback/domain/playback_queue.dart';
import 'package:clutter/shared/services/log.dart';

class PlaybackRelease {
  final String songId;
  final bool wasPlaying;
  final Duration position;

  const PlaybackRelease({
    required this.songId,
    required this.wasPlaying,
    required this.position,
  });
}

/// owns playback policy while the audio player port owns platform audio.
///
/// keeping those jobs separate lets queue and lifecycle behavior be tested
/// without starting an audio service or opening a real file.
class PlaybackController extends ChangeNotifier {
  final PlaybackPersistence persistence;
  final AudioPlayerPort player;
  final PlaybackQueue queueState = PlaybackQueue();

  PlaybackController({required this.persistence, required this.player}) {
    _listenToPlayer();
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _stateSaveTimer;
  SongViewData? _currentSong;
  Duration? _duration;
  Duration? _position;
  int? _savedPositionMs;
  bool _isPlaying = false;
  bool _isFinished = false;
  bool _isScrubbing = false;
  bool _loopOne = false;
  bool _loopQueue = false;
  double _volume = 1;

  SongViewData? get currentSong => _currentSong;
  Duration? get duration => _duration;
  Duration? get position => _position;
  bool get isPlaying => _isPlaying;
  bool get isFinished => _isFinished;
  bool get isScrubbing => _isScrubbing;
  bool get loopOne => _loopOne;
  bool get loopQueue => _loopQueue;
  double get volume => _volume;
  List<SongViewData> get queue => queueState.upNext;
  bool get canPlayPrevious => _currentSong != null || queueState.hasPrevious;

  Future<void> hydrate() async {
    final saved = await persistence.loadPlaybackState();
    if (saved == null) return;
    _currentSong = saved.song;
    _savedPositionMs = saved.positionMs;
    // the source is not loaded yet; first play consumes this saved position
    _position = Duration(milliseconds: saved.positionMs);
    _loopOne = saved.loopOne;
    notifyListeners();
  }

  Future<List<SongViewData>> recentlyPlayed({int limit = 50}) =>
      persistence.getRecentlyPlayed(limit);

  Future<void> playSongById(String id, Iterable<SongViewData> songs) async {
    final song = songs.where((candidate) => candidate.id == id).firstOrNull;
    if (song == null) return;
    if (_currentSong?.id == id) {
      await _restartCurrent();
      return;
    }
    if (_currentSong != null) queueState.remember(_currentSong!);
    await _playNow(song);
  }

  Future<void> playSongsFromStart(List<SongViewData> songs) async {
    if (songs.isEmpty) return;
    if (_currentSong != null) queueState.remember(_currentSong!);
    queueState.replaceQueue(songs.skip(1));
    queueState.syncLoopSnapshot(songs.first);
    await _playNow(songs.first);
  }

  Future<void> _playNow(SongViewData song) async {
    _currentSong = song;
    _isFinished = false;
    _savedPositionMs = null;
    _position = Duration.zero;
    await player.loadAndPlay(song);
    await player.setLoopOne(_loopOne);
    notifyListeners();
    // these writes should not delay playback, and both methods handle errors
    unawaited(_recordPlay(song.id));
    unawaited(_saveState());
    _ensureStateTimer();
  }

  Future<void> _recordPlay(String songId) async {
    try {
      await persistence.recordPlay(songId);
    } catch (error) {
      Log.e('record play failed', error);
    }
  }

  Future<void> playNext() async {
    if (!queueState.hasNext) {
      if (_loopQueue && queueState.restartLoop().isNotEmpty) {
        final loop = queueState.restartLoop();
        queueState.replaceQueue(loop.skip(1));
        await _playNow(loop.first);
        return;
      }
      _isPlaying = false;
      _isFinished = true;
      await player.seek(_duration ?? Duration.zero);
      notifyListeners();
      unawaited(_saveState());
      return;
    }
    if (_currentSong != null) queueState.remember(_currentSong!);
    await _playNow(queueState.takeNext());
  }

  Future<void> playPrevious() async {
    if (_currentSong == null || _isFinished) {
      if (!queueState.hasPrevious) return;
      await _playNow(queueState.takePrevious());
      return;
    }
    final seconds = _position?.inSeconds ?? 0;
    if (seconds >= 3 || !queueState.hasPrevious) {
      await _restartCurrent();
      return;
    }
    queueState.addNext(_currentSong!);
    await _playNow(queueState.takePrevious());
  }

  Future<void> _restartCurrent() async {
    final song = _currentSong;
    if (song == null) return;
    _position = Duration.zero;
    _isFinished = false;
    if (_savedPositionMs != null) {
      _savedPositionMs = null;
      await player.loadAndPlay(song, startPosition: Duration.zero);
      await player.setLoopOne(_loopOne);
      unawaited(_recordPlay(song.id));
      _ensureStateTimer();
    } else {
      await player.seek(Duration.zero);
      if (!_isPlaying) await player.play();
    }
    notifyListeners();
    unawaited(_saveState());
  }

  Future<void> _handleTrackComplete() async {
    if (_loopOne) {
      final song = _currentSong;
      if (song != null) {
        _position = Duration.zero;
        _isFinished = false;
        await player.loadAndPlay(song, startPosition: Duration.zero);
        await player.setLoopOne(true);
        notifyListeners();
        unawaited(_saveState());
        _ensureStateTimer();
      }
      return;
    }
    await playNext();
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      await player.pause();
      notifyListeners();
      unawaited(_saveState());
      return;
    }
    final song = _currentSong;
    if (song == null) return;
    if (_savedPositionMs != null || _isFinished) {
      final start = Duration(milliseconds: _savedPositionMs ?? 0);
      _savedPositionMs = null;
      _isFinished = false;
      await player.loadAndPlay(song, startPosition: start);
      await player.setLoopOne(_loopOne);
      unawaited(_recordPlay(song.id));
    } else {
      await player.play();
    }
    notifyListeners();
    unawaited(_saveState());
    _ensureStateTimer();
  }

  Future<void> pause() async {
    if (_currentSong == null) return;
    await player.pause();
    notifyListeners();
    unawaited(_saveState());
  }

  Future<void> resume() async {
    if (_currentSong == null) return;
    await player.play();
    notifyListeners();
    unawaited(_saveState());
    _ensureStateTimer();
  }

  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped == _volume) return;
    _volume = clamped;
    await player.setVolume(clamped);
    notifyListeners();
  }

  Future<void> toggleLoopOne() async {
    _loopOne = !_loopOne;
    await player.setLoopOne(_loopOne);
    notifyListeners();
    unawaited(_saveState());
  }

  void toggleLoopQueue() {
    _loopQueue = !_loopQueue;
    if (_loopQueue) queueState.syncLoopSnapshot(_currentSong);
    notifyListeners();
  }

  void setPosition(double value) {
    if (_currentSong == null) return;
    final next = Duration(milliseconds: value.toInt());
    if (_savedPositionMs != null) _savedPositionMs = next.inMilliseconds;
    _position = next;
    notifyListeners();
  }

  Future<void> seekBy(Duration offset) async {
    if (_currentSong == null) return;
    final durationMs = _duration?.inMilliseconds;
    var targetMs =
        (_position ?? Duration.zero).inMilliseconds + offset.inMilliseconds;
    if (targetMs < 0) targetMs = 0;
    if (durationMs != null && durationMs > 0 && targetMs > durationMs) {
      targetMs = durationMs;
    }
    final target = Duration(milliseconds: targetMs);
    if (_savedPositionMs != null) {
      _savedPositionMs = targetMs;
    } else {
      await player.seek(target);
    }
    _position = target;
    if (durationMs == null || targetMs < durationMs) _isFinished = false;
    notifyListeners();
    unawaited(_saveState());
  }

  Future<void> startScrub() async {
    if (_currentSong == null) return;
    _isScrubbing = true;
    await player.pause();
    notifyListeners();
    unawaited(_saveState());
  }

  Future<void> endScrub() async {
    if (_currentSong == null) {
      _isScrubbing = false;
      return;
    }
    _isScrubbing = false;
    if (_savedPositionMs == null && _position != null) {
      await player.seek(_position!);
    }
    await player.play();
    notifyListeners();
    unawaited(_saveState());
    _ensureStateTimer();
  }

  void addToQueue(SongViewData song) {
    queueState.add(song);
    queueState.syncLoopSnapshot(_currentSong);
    notifyListeners();
  }

  void addAllToQueue(Iterable<SongViewData> songs) {
    queueState.addAll(songs);
    queueState.syncLoopSnapshot(_currentSong);
    notifyListeners();
  }

  void playNextInQueue(SongViewData song) {
    queueState.addNext(song);
    queueState.syncLoopSnapshot(_currentSong);
    notifyListeners();
  }

  void moveQueueItem(int from, int to) {
    queueState.move(from, to);
    queueState.syncLoopSnapshot(_currentSong);
    notifyListeners();
  }

  void shuffleQueue({Random? random}) {
    if (!queueState.shuffle(random: random)) return;
    queueState.syncLoopSnapshot(_currentSong);
    notifyListeners();
  }

  void removeQueueItem(int index) {
    queueState.removeAt(index);
    queueState.syncLoopSnapshot(_currentSong);
    notifyListeners();
  }

  void clearQueue() {
    queueState.clear();
    notifyListeners();
  }

  void reconcile(Iterable<SongViewData> songs) {
    final byId = {for (final song in songs) song.id: song};
    if (_currentSong != null) _currentSong = byId[_currentSong!.id];
    queueState.reconcile(byId);
    notifyListeners();
  }

  Future<PlaybackRelease?> releaseForEdit(Set<String> affectedIds) async {
    final song = _currentSong;
    if (song == null || !affectedIds.contains(song.id)) return null;
    final release = PlaybackRelease(
      songId: song.id,
      wasPlaying: _isPlaying,
      position: _position ?? Duration.zero,
    );
    await player.stop();
    notifyListeners();
    return release;
  }

  Future<void> restoreAfterEdit(
    PlaybackRelease release,
    Iterable<SongViewData> songs,
  ) async {
    final refreshed = songs
        .where((song) => song.id == release.songId)
        .firstOrNull;
    if (refreshed == null) return;
    await player.loadAndPlay(refreshed, startPosition: release.position);
    if (!release.wasPlaying) await player.pause();
    _currentSong = refreshed;
    notifyListeners();
  }

  Future<void> removeSongs(Set<String> ids) async {
    queueState.removeIds(ids);
    if (_currentSong != null && ids.contains(_currentSong!.id)) {
      await stopAndClear();
    }
    notifyListeners();
  }

  Future<void> removeMissingSongs(Iterable<SongViewData> songs) async {
    final liveIds = songs.map((song) => song.id).toSet();
    final staleIds = {
      for (final song in queueState.upNext)
        if (!liveIds.contains(song.id)) song.id,
      if (_currentSong != null && !liveIds.contains(_currentSong!.id))
        _currentSong!.id,
    };
    if (staleIds.isNotEmpty) await removeSongs(staleIds);
    reconcile(songs);
  }

  Future<void> reset() async {
    queueState.reset();
    await stopAndClear();
  }

  Future<void> stopAndClear() async {
    await player.stop();
    _currentSong = null;
    _isPlaying = false;
    _isFinished = false;
    _duration = null;
    _position = null;
    _savedPositionMs = null;
    notifyListeners();
    unawaited(_saveState());
  }

  Future<void> _saveState() async {
    try {
      await persistence.savePlaybackState(
        _currentSong?.id,
        _savedPositionMs ?? _position?.inMilliseconds ?? 0,
        _loopOne,
      );
    } catch (error) {
      Log.e('save playback state', error);
    }
  }

  void _ensureStateTimer() {
    _stateSaveTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isPlaying) unawaited(_saveState());
    });
  }

  void _listenToPlayer() {
    // subscriptions are stored so dispose can stop callbacks reaching dead ui
    player
      ..onSkipToNext = playNext
      ..onSkipToPrevious = playPrevious
      ..onTrackComplete = _handleTrackComplete;
    _subscriptions.add(player.playbackStateStream.listen(_readPlaybackState));
    _subscriptions.add(player.mediaItemStream.listen(_readMediaItem));
    _subscriptions.add(player.positionStream.listen(_readPosition));
  }

  void _readPlaybackState(PlaybackState state) {
    _isPlaying = state.playing;
    if (state.processingState == AudioProcessingState.completed && !_loopOne) {
      _isFinished = true;
    }
    notifyListeners();
  }

  void _readMediaItem(MediaItem? item) {
    final duration = item?.duration;
    if (duration == null || duration <= Duration.zero) return;
    _duration = duration;
    notifyListeners();
  }

  void _readPosition(Duration position) {
    if (_isScrubbing) return;
    _position = position;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _stateSaveTimer?.cancel();
    // dispose is best effort on shutdown, the periodic save is the main guard
    unawaited(_saveState());
    super.dispose();
  }
}

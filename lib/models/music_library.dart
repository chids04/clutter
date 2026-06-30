import 'dart:async';
import 'dart:collection';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:clutter/services/audio_handler.dart';
import 'package:clutter/utils/log.dart';
import 'package:clutter/src/rust/api/scanner.dart';

enum QuickPlayKind { song, album, playlist }

enum LibraryPage {
  songs("songs"),
  albums("albums"),
  artists("artists"),
  playlists("playlists"),
  recentlyPlayed("recently played");

  final String label;

  const LibraryPage(this.label);
}

/// Thin Dart-side state container. Storage and metadata extraction all live
/// on the Rust side; this class owns the scan lifecycle, a cached paginated
/// view over the SQLite-backed library, and the now-playing queue + history.
/// Audio playback itself is delegated to the platform audio service via
/// [ClutterAudioHandler].
class MusicLibrary extends ChangeNotifier {
  MusicLibrary({
    required this.library,
    required ClutterAudioHandler handler,
    required String musicDir,
  }) : _handler = handler,
       _musicDir = musicDir {
    _initHandlerEvents();
    _refreshTotal();
    unawaited(hydrate());
  }

  final CLibrary library;
  final ClutterAudioHandler _handler;
  final String _musicDir;

  final List<String> _directories = [];
  final Set<String> _directorySet = {};
  List<SongViewData> _songs = const [];
  List<AlbumViewData> _albums = const [];
  List<PlaylistViewData> _playlists = const [];
  List<ArtistViewData> _artists = const [];
  int _totalSongs = 0;
  int _totalAlbums = 0;
  int _totalPlaylists = 0;
  int _totalArtists = 0;
  String? _likedSongsPlaylistId;
  Set<String> _likedSongIds = <String>{};
  bool _isScanning = false;
  bool _isPlaying = false;
  bool _isFinished = false;
  SongViewData? _currentSong;

  // quick-play sidebar pins
  List<PinnedItemData> _pinnedItems = [];

  // toast pill state (shown above MediaBar)
  String? _toastMessage;
  Timer? _toastTimer;

  // audio player state
  final List<SongViewData> _queue = [];
  final List<SongViewData> _history = [];
  final List<SongViewData> _queueLoopSnapshot = [];
  final List<StreamSubscription> _subs = [];
  Duration? _duration;
  Duration? _position;
  bool _isScrubbing = false;
  bool _loopOne = false;
  bool _loopQueue = false;
  double _volume = 1.0;

  // hold the current state of the views

  // When non-null, a pending saved playback position that hasn't been loaded
  // into the audio player yet. Set by hydrate() on app relaunch; consumed on
  // first user-initiated play. While active, the slider displays this value
  // and user scrubs update it in place rather than seeking a stopped player.
  int? _savedPositionMs;
  Timer? _stateSaveTimer;

  // getters
  UnmodifiableListView<String> get directories =>
      UnmodifiableListView(_directories);
  UnmodifiableListView<SongViewData> get songs => UnmodifiableListView(_songs);
  UnmodifiableListView<AlbumViewData> get albums =>
      UnmodifiableListView(_albums);
  UnmodifiableListView<PlaylistViewData> get playlists =>
      UnmodifiableListView(_playlists);
  UnmodifiableListView<ArtistViewData> get artists =>
      UnmodifiableListView(_artists);
  UnmodifiableListView<SongViewData> get queue => UnmodifiableListView(_queue);
  int get totalSongs => _totalSongs;
  int get totalAlbums => _totalAlbums;
  int get totalPlaylists => _totalPlaylists;
  int get totalArtists => _totalArtists;
  bool get isScanning => _isScanning;
  bool get isPlaying => _isPlaying;
  bool get isScrubbing => _isScrubbing;
  bool get isFinished => _isFinished;
  bool get loopOne => _loopOne;
  bool get loopQueue => _loopQueue;
  SongViewData? get currentSong => _currentSong;
  Duration? get playerDuration => _duration;
  Duration? get playerPosition => _position;
  double get volume => _volume;
  String? get toastMessage => _toastMessage;
  UnmodifiableListView<PinnedItemData> get pinnedItems =>
      UnmodifiableListView(_pinnedItems);
  String get musicDir => _musicDir;
  bool get usesSandboxMusicFolder =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool isLiked(String songId) => _likedSongIds.contains(songId);
  bool get canPlayPrevious => _currentSong != null || _history.isNotEmpty;

  /// Combines `primaryArtist` and any features into a single display string.
  String artistsDisplay(SongViewData song) {
    if (song.featuredArtists.isEmpty) return song.primaryArtist;
    return "${song.primaryArtist} feat. ${song.featuredArtists.join(', ')}";
  }

  void _refreshTotal() {
    _totalSongs = library.getTotalSongs();
    _totalAlbums = library.getTotalAlbums();
    _totalPlaylists = library.getTotalPlaylists();
    _totalArtists = library.getTotalArtists();
  }

  /// Pull persisted state out of SQLite on boot: scan paths, then playback
  /// state (last song + position), then the full library cache. Playback is
  /// restored paused — the user must press play to actually start audio.
  Future<void> hydrate() async {
    final paths = await library.getScanPaths();
    for (final p in paths) {
      if (_directorySet.add(p)) _directories.add(p);
    }
    final saved = await library.loadPlaybackState();
    if (saved != null) {
      _currentSong = saved.song;
      _savedPositionMs = saved.positionMs;
      _position = Duration(milliseconds: saved.positionMs);
      _loopOne = saved.loopOne;
    }
    await _reloadPins();
    await _reloadSongs();
  }

  Future<void> _reloadPins() async {
    try {
      _pinnedItems = await library.getPinnedItems();
    } catch (e) {
      Log.e("reload pins failed", e);
      _pinnedItems = [];
    }
    notifyListeners();
  }

  Future<void> _reloadSongs() async {
    _refreshTotal();
    if (_totalSongs == 0) {
      _songs = const [];
    } else {
      _songs = await library.getSongsPaginated(offset: 0, limit: _totalSongs);
    }
    if (_totalAlbums == 0) {
      _albums = const [];
    } else {
      _albums = await library.getAlbumsPaginated(
        offset: 0,
        limit: _totalAlbums,
      );
    }
    if (_totalArtists == 0) {
      _artists = const [];
    } else {
      _artists = await library.getArtistsPaginated(
        offset: 0,
        limit: _totalArtists,
      );
    }
    await _reloadPlaylists();
  }

  Future<void> _reloadPlaylists() async {
    _totalPlaylists = library.getTotalPlaylists();
    _playlists = _totalPlaylists == 0
        ? const []
        : await library.getPlaylistsPaginated(
            offset: 0,
            limit: _totalPlaylists,
          );
    _likedSongsPlaylistId = await library.getLikedSongsPlaylistId();
    final ids = await library.getLikedSongIds();
    _likedSongIds = ids.toSet();
    notifyListeners();
  }

  static String _kindString(QuickPlayKind kind) {
    return switch (kind) {
      QuickPlayKind.song => 'song',
      QuickPlayKind.album => 'album',
      QuickPlayKind.playlist => 'playlist',
    };
  }

  bool isPinned({required String id, required QuickPlayKind kind}) {
    final k = _kindString(kind);
    return _pinnedItems.any((p) => p.itemId == id && p.kind == k);
  }

  Future<void> pinItem({
    required String id,
    required QuickPlayKind kind,
  }) async {
    final k = _kindString(kind);
    try {
      await library.pinItem(itemId: id, kind: k);
      await _reloadPins();
    } catch (e) {
      Log.e("pin item $id ($k)", e);
    }
  }

  Future<void> unpinItem({
    required String id,
    required QuickPlayKind kind,
  }) async {
    final k = _kindString(kind);
    try {
      await library.unpinItem(itemId: id, kind: k);
      await _reloadPins();
    } catch (e) {
      Log.e("unpin item $id ($k)", e);
    }
  }

  Future<void> movePinnedItem(int from, int to) async {
    final pins = List<PinnedItemData>.from(_pinnedItems);
    if (from < 0 || from >= pins.length || to < 0 || to >= pins.length) {
      return;
    }
    final item = pins.removeAt(from);
    pins.insert(to, item);
    _pinnedItems = pins;
    notifyListeners();
    try {
      await library.movePinnedItem(
        itemId: item.itemId,
        kind: item.kind,
        newIndex: to,
      );
      await _reloadPins();
    } catch (e) {
      Log.e("move pinned item $from -> $to", e);
      await _reloadPins();
    }
  }

  /// Fetch all songs for a single album, ordered by disc/track. Live query —
  /// doesn't touch any cached state.
  Future<List<SongViewData>> fetchAlbumSongs(String albumId) {
    return library.getSongsByAlbumId(albumId: albumId);
  }

  Future<List<SongViewData>> fetchPlaylistSongs(String playlistId) {
    return library.getSongsInPlaylist(playlistId: playlistId);
  }

  // --- search passthroughs ---

  Future<List<SongViewData>> searchSongs(String query) async {
    final q = query.trim();
    if (q.isEmpty) return _songs;
    return library.searchSongs(query: q, limit: 200);
  }

  Future<List<AlbumViewData>> searchAlbums(String query) async {
    final q = query.trim();
    if (q.isEmpty) return _albums;
    return library.searchAlbums(query: q, limit: 200);
  }

  Future<List<PlaylistViewData>> searchPlaylists(String query) async {
    final q = query.trim();
    if (q.isEmpty) return _playlists;
    return library.searchPlaylists(query: q, limit: 200);
  }

  Future<List<ArtistViewData>> searchArtists(String query) async {
    final q = query.trim();
    if (q.isEmpty) return _artists;
    return library.searchArtists(query: q, limit: 200);
  }

  Future<List<AlbumViewData>> fetchArtistAlbums(String artistId) {
    return library.getAlbumsByArtistId(artistId: artistId);
  }

  Future<List<AlbumViewData>> fetchArtistFeaturedAlbums(String artistId) {
    return library.getAlbumsArtistFeaturedOn(artistId: artistId);
  }

  Future<List<SongViewData>> fetchArtistFeaturedSongs(String artistId) {
    return library.getSongsArtistFeaturedOn(artistId: artistId);
  }

  // --- playlist CRUD & song membership ---

  Future<String> createPlaylist(String name) async {
    final id = await library.createPlaylist(name: name);
    await _reloadPlaylists();
    return id;
  }

  Future<void> deletePlaylist(String id) async {
    await library.deletePlaylist(id: id);
    await _reloadPlaylists();
  }

  Future<void> addSongToPlaylist(String playlistId, SongViewData song) async {
    await library.addSongToPlaylist(playlistId: playlistId, songId: song.id);
    String playlistName = "playlist";
    for (final p in _playlists) {
      if (p.id == playlistId) {
        playlistName = p.name;
        break;
      }
    }
    showToast("${song.title} added to $playlistName");
    await _reloadPlaylists();
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    await library.removeSongFromPlaylist(
      playlistId: playlistId,
      songId: songId,
    );
    await _reloadPlaylists();
  }

  Future<void> toggleLiked(SongViewData song) async {
    final pid = _likedSongsPlaylistId;
    if (pid == null) return;
    if (_likedSongIds.contains(song.id)) {
      await library.removeSongFromPlaylist(playlistId: pid, songId: song.id);
      _likedSongIds.remove(song.id);
      notifyListeners();
      // silent on un-like per spec
    } else {
      await library.addSongToPlaylist(playlistId: pid, songId: song.id);
      _likedSongIds.add(song.id);
      showToast("${song.title} added to Liked Songs");
    }
    // Refresh counts / ordering of playlists cache.
    unawaited(_reloadPlaylists());
  }

  void showToast(String message) {
    _toastMessage = message;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toastMessage = null;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> addDirectory(String directory) async {
    if (!_directorySet.add(directory)) return;
    _directories.add(directory);
    _isScanning = true;
    notifyListeners();

    try {
      await library.scanDirectory(
        path: directory,
        config: const Config(isDeezer: true),
      );
      await _reloadSongs();
      showToast("scanned $directory");
    } catch (e) {
      Log.e("scan failed for $directory", e);
      showToast("scan failed");
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> setScanDirectory(String directory) async {
    if (_isScanning) return;

    final oldDirectories = List<String>.from(_directories);
    for (final oldDirectory in oldDirectories) {
      if (oldDirectory == directory) continue;
      try {
        await library.deleteScanPath(path: oldDirectory);
      } catch (e) {
        Log.e("delete old scan path failed for $oldDirectory", e);
      }
    }
    _directories
      ..clear()
      ..add(directory);
    _directorySet
      ..clear()
      ..add(directory);
    await _purgeAfterDelete();

    await rescanDirectory(directory);
  }

  Future<void> rescanDirectory(String directory) async {
    if (!_directorySet.contains(directory)) return;
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();
    final before = _songs.length;
    try {
      await library.scanDirectory(
        path: directory,
        config: const Config(isDeezer: true),
      );
      await _reloadSongs();
      final added = _songs.length - before;
      showToast(
        added <= 0
            ? "no new songs in $directory"
            : "added $added song${added == 1 ? '' : 's'} from $directory",
      );
    } catch (e) {
      Log.e("rescan failed for $directory", e);
      showToast("rescan failed");
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> removeDirectory(String directory) async {
    if (!_directorySet.contains(directory)) return;
    int removed = 0;
    try {
      removed = await library.deleteScanPath(path: directory);
    } catch (e) {
      Log.e("delete path failed for $directory", e);
    }
    _directorySet.remove(directory);
    _directories.remove(directory);
    await _purgeAfterDelete();
    showToast(
      removed == 0
          ? "removed $directory"
          : "removed $removed song${removed == 1 ? '' : 's'} from $directory",
    );
  }

  Future<void> resetLibrary() async {
    await _stopPlayback();
    _directories.clear();
    _directorySet.clear();
    _songs = const [];
    _albums = const [];
    _queue.clear();
    _history.clear();
    _setQueueLoopSnapshot(const []);
    await library.resetLibrary();
    await _reloadSongs();
  }

  /// Remove a single song from the library. If it's currently playing,
  /// playback stops and the MediaBar clears.
  Future<void> deleteSong(String id) async {
    try {
      await library.deleteSong(id: id);
    } catch (e) {
      Log.e("delete song $id", e);
      return;
    }
    _queue.removeWhere((s) => s.id == id);
    _history.removeWhere((s) => s.id == id);
    _removeFromQueueLoopSnapshot({id});
    if (_currentSong?.id == id) {
      await _stopPlayback();
    }
    await _purgeAfterDelete();
  }

  /// Remove an entire album (and all its songs).
  Future<void> deleteAlbum(String albumId) async {
    final songsInAlbum = await library.getSongsByAlbumId(albumId: albumId);
    final ids = songsInAlbum.map((s) => s.id).toSet();
    try {
      await library.deleteAlbum(id: albumId);
    } catch (e) {
      Log.e("delete album $albumId", e);
      return;
    }
    _queue.removeWhere((s) => ids.contains(s.id));
    _history.removeWhere((s) => ids.contains(s.id));
    _removeFromQueueLoopSnapshot(ids);
    if (_currentSong != null && ids.contains(_currentSong!.id)) {
      await _stopPlayback();
    }
    await _purgeAfterDelete();
  }

  Future<List<SongViewData>> fetchRecentlyPlayed({int limit = 50}) {
    return library.getRecentlyPlayed(limit: limit);
  }

  Future<void> _stopPlayback() async {
    await _handler.stop();
    _currentSong = null;
    _isPlaying = false;
    _position = null;
    _duration = null;
    _savedPositionMs = null;
    _setQueueLoopSnapshot(const []);
    try {
      await library.savePlaybackState(
        songId: null,
        positionMs: 0,
        loopOne: _loopOne,
      );
    } catch (e) {
      Log.e("clear playback state", e);
    }
  }

  Future<void> _purgeAfterDelete() async {
    await _reloadSongs();
  }

  void _setQueueLoopSnapshot(Iterable<SongViewData> songs) {
    _queueLoopSnapshot
      ..clear()
      ..addAll(songs);
    if (_queueLoopSnapshot.isEmpty) _loopQueue = false;
  }

  void _syncQueueLoopSnapshotFromPlayback() {
    _setQueueLoopSnapshot([?_currentSong, ..._queue]);
  }

  void _removeFromQueueLoopSnapshot(Set<String> songIds) {
    _queueLoopSnapshot.removeWhere((s) => songIds.contains(s.id));
    if (_queueLoopSnapshot.isEmpty) _loopQueue = false;
  }

  /// Start playing [song] immediately. All public playback entry points
  /// funnel through here so swapping in a Rust audio backend later only
  /// requires changing this one method.
  Future<void> _playNow(SongViewData song) async {
    _currentSong = song;
    _isPlaying = true;
    _isFinished = false;
    _savedPositionMs = null;
    await _handler.loadAndPlay(song);
    await _handler.setLoopOne(_loopOne);
    notifyListeners();
    unawaited(_recordPlay(song.id));
    unawaited(_saveState());
    _ensureStateTimer();
  }

  Future<void> _recordPlay(String songId) async {
    try {
      await library.recordPlay(songId: songId);
    } catch (e) {
      Log.e("record play $songId", e);
    }
  }

  Future<void> onPlaySong(String id) async {
    final song = await library.getSongById(id: id);
    if (song == null) {
      Log.e("song $id not found");
      return;
    }
    if (_currentSong != null) _history.add(_currentSong!);
    await _playNow(song);
    _syncQueueLoopSnapshotFromPlayback();
    notifyListeners();
  }

  Future<void> playSongsFromStart(List<SongViewData> songs) async {
    if (songs.isEmpty) return;
    if (_currentSong != null) _history.add(_currentSong!);
    _queue.clear();
    _queue.addAll(songs.skip(1));
    _setQueueLoopSnapshot(songs);
    await _playNow(songs.first);
  }

  /// Advance to the next queued song. If the queue is empty, mark the current
  /// song as finished but keep the audio-service session alive so headset
  /// controls remain available.
  Future<void> playNext() async {
    if (_currentSong == null) return;

    if (_queue.isEmpty) {
      if (_loopQueue && _queueLoopSnapshot.isNotEmpty) {
        if (_currentSong != null) _history.add(_currentSong!);
        _queue.clear();
        _queue.addAll(_queueLoopSnapshot.skip(1));
        await _playNow(_queueLoopSnapshot.first);
        return;
      }

      _isPlaying = false;
      _isFinished = true;

      _handler.seek(_duration ?? Duration(microseconds: 0));
      notifyListeners();
      unawaited(_saveState());
      return;
    }

    if (_currentSong != null) _history.add(_currentSong!);
    await _playNow(_queue.removeAt(0));
  }

  void loopSong() {
    if (_currentSong == null) return;
    _isPlaying = true;
  }

  /// If less than 3 s into the current song, go back one in history. Otherwise
  /// restart the current song. When the current song has finished naturally,
  /// always go back to history.
  Future<void> playPrevious() async {
    if (_currentSong == null || _isFinished) {
      if (_history.isEmpty) return;
      await _playNow(_history.removeLast());
      return;
    }
    final pos = _position?.inSeconds ?? 0;
    if (pos >= 3 || _history.isEmpty) {
      // Cold-start from saved state: slider resets without touching the player.
      if (_savedPositionMs != null) {
        _savedPositionMs = 0;
        _position = Duration.zero;
        notifyListeners();
        unawaited(_saveState());
        return;
      }
      await _handler.seek(Duration.zero);
      _position = Duration.zero;
      if (!_isPlaying) {
        await _handler.play();
        _isPlaying = true;
      }
      notifyListeners();
      unawaited(_saveState());
      return;
    }
    if (_currentSong != null) _queue.insert(0, _currentSong!);
    await _playNow(_history.removeLast());
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      await _handler.pause();
      _isPlaying = false;
      notifyListeners();
      unawaited(_saveState());
      return;
    }
    // Cold-start from a hydrated playback_state row: load the source for the
    // first time and seek to the stored offset before starting audio.
    if (_savedPositionMs != null && _currentSong != null) {
      final song = _currentSong!;
      final startPos = Duration(milliseconds: _savedPositionMs!);
      _savedPositionMs = null;
      _isPlaying = true;
      await _handler.loadAndPlay(song, startPosition: startPos);
      await _handler.setLoopOne(_loopOne);
      notifyListeners();
      unawaited(_recordPlay(song.id));
      unawaited(_saveState());
      _ensureStateTimer();
      return;
    }

    if (_currentSong == null) {
      return;
    }

    if (_isFinished) {
      final song = _currentSong!;
      _isFinished = false;
      _isPlaying = true;
      await _handler.loadAndPlay(song, startPosition: Duration.zero);
      await _handler.setLoopOne(_loopOne);
      notifyListeners();
      unawaited(_recordPlay(song.id));
      unawaited(_saveState());
      _ensureStateTimer();
      return;
    }

    await _handler.play();
    _isPlaying = true;
    notifyListeners();
    unawaited(_saveState());
    _ensureStateTimer();
  }

  void pause() {
    if (_currentSong == null) return;
    _handler.pause();
    _isPlaying = false;
    notifyListeners();
    unawaited(_saveState());
  }

  void resume() {
    if (_currentSong == null) return;
    _handler.play();
    _isPlaying = true;
    notifyListeners();
    unawaited(_saveState());
    _ensureStateTimer();
  }

  Future<void> setVolume(double v) async {
    final clamped = v.clamp(0.0, 1.0);
    if (clamped == _volume) return;
    _volume = clamped;
    await _handler.setVolume(clamped);
    notifyListeners();
  }

  Future<void> toggleLoopOne() async {
    _loopOne = !_loopOne;
    await _handler.setLoopOne(_loopOne);
    notifyListeners();
    unawaited(_saveState());
  }

  void toggleLoopQueue() {
    _loopQueue = !_loopQueue;
    if (_loopQueue && _queueLoopSnapshot.isEmpty) {
      _syncQueueLoopSnapshotFromPlayback();
    }
    notifyListeners();
  }

  void setPlayerPosition(double value) {
    if (_currentSong == null) return;
    final newPos = Duration(milliseconds: value.toInt());
    if (_savedPositionMs != null) {
      _savedPositionMs = newPos.inMilliseconds;
    }
    _position = newPos;
    notifyListeners();
  }

  /// Called when the user begins dragging the position slider. Pauses playback
  /// and suppresses AudioService.position updates until [endScrub] so the thumb
  /// does not snap back to stale positions.
  void startScrub() {
    if (_currentSong == null) return;
    _isScrubbing = true;
    _handler.pause();
    _isPlaying = false;
    notifyListeners();
    unawaited(_saveState());
  }

  /// Called when the user releases the position slider. Commits the seek and
  /// resumes playback.
  void endScrub() {
    if (_currentSong == null) {
      _isScrubbing = false;
      return;
    }
    _isScrubbing = false;
    if (_savedPositionMs == null && _position != null) {
      _handler.seek(_position!).then((_) => unawaited(_saveState()));
    } else {
      unawaited(_saveState());
    }
    _handler.play();
    _isPlaying = true;
    notifyListeners();
    _ensureStateTimer();
  }

  Future<void> _saveState() async {
    try {
      await library.savePlaybackState(
        songId: _currentSong?.id,
        positionMs: _savedPositionMs ?? _position?.inMilliseconds ?? 0,
        loopOne: _loopOne,
      );
    } catch (e) {
      Log.e("save playback state", e);
    }
  }

  void _ensureStateTimer() {
    _stateSaveTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isPlaying) unawaited(_saveState());
    });
  }

  void queueSong(SongViewData song) {
    _queue.add(song);
    _syncQueueLoopSnapshotFromPlayback();
    notifyListeners();
  }

  void queueSongs(List<SongViewData> songs, {required String label}) {
    if (songs.isEmpty) {
      showToast("$label has no songs");
      return;
    }
    _queue.addAll(songs);
    _syncQueueLoopSnapshotFromPlayback();
    showToast(
      "Added ${songs.length} ${songs.length == 1 ? 'song' : 'songs'} to queue",
    );
  }

  /// Insert [song] at the front of the queue — "play next" semantics.
  void queueSongNext(SongViewData song) {
    _queue.insert(0, song);
    _syncQueueLoopSnapshotFromPlayback();
    notifyListeners();
  }

  void moveQueueItem(int from, int to) {
    if (from == to) return;
    final item = _queue.removeAt(from);
    _queue.insert(to, item);
    _syncQueueLoopSnapshotFromPlayback();
    notifyListeners();
  }

  void removeFromQueue(int index) {
    _queue.removeAt(index);
    _syncQueueLoopSnapshotFromPlayback();
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _setQueueLoopSnapshot(const []);
    notifyListeners();
  }

  Future<void> chooseOrScanMusicFolder() async {
    if (usesSandboxMusicFolder) {
      await setScanDirectory(_musicDir);
      return;
    }

    try {
      final directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: "select directory to scan for music",
      );
      if (directory != null) await setScanDirectory(directory);
    } on PlatformException catch (e) {
      Log.e("unsupported file picker op", e);
      showToast("folder picker unavailable");
    }
  }

  void _initHandlerEvents() {
    _handler
      ..onSkipToNext = playNext
      ..onSkipToPrevious = playPrevious;

    _subs.add(
      _handler.playbackState.listen((state) {
        _isPlaying = state.playing;
        if (state.processingState == AudioProcessingState.completed &&
            !_loopOne) {
          _isFinished = true;
        }
        notifyListeners();
      }),
    );
    _subs.add(
      _handler.mediaItem.listen((item) {
        final duration = item?.duration;
        if (duration != null && duration > Duration.zero) {
          _duration = duration;
          notifyListeners();
        }
      }),
    );
    _subs.add(
      AudioService.position.listen((position) {
        if (_isScrubbing) return;
        _position = position;
        notifyListeners();
      }),
    );
  }

  @override
  void dispose() {
    for (var s in _subs) {
      s.cancel();
    }
    _toastTimer?.cancel();
    _stateSaveTimer?.cancel();
    // Best-effort final flush. `dispose()` isn't guaranteed to run on a hard
    // kill — the 5 s periodic timer covers that case.
    unawaited(_saveState());
    // The handler lifecycle is managed by AudioService; do not dispose it here.
    super.dispose();
  }
}

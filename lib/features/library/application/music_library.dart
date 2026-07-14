import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:clutter/features/library/application/library_catalog_controller.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/application/playback_controller.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';
import 'package:clutter/features/scanning/application/library_scan_controller.dart';
import 'package:clutter/shared/presentation/toast_controller.dart';
import 'package:clutter/shared/services/log.dart';

/// the provider-facing facade used by existing widgets.
///
/// widgets keep one stable api while catalog, scan, playback and toast state
/// have separate owners. this class only coordinates work crossing features.
class MusicLibrary extends ChangeNotifier {
  final LibraryCatalogController catalog;
  final LibraryScanController scanner;
  final PlaybackController playback;
  final ToastController toasts;

  factory MusicLibrary({
    required LibraryCatalogRepository catalogRepository,
    required PlaybackPersistence playbackPersistence,
    required AudioPlayerPort player,
    required String musicDir,
  }) {
    final catalog = LibraryCatalogController(catalogRepository);
    return MusicLibrary._(
      catalog: catalog,
      scanner: LibraryScanController(
        repository: catalogRepository,
        catalog: catalog,
        musicDirectory: musicDir,
      ),
      playback: PlaybackController(
        persistence: playbackPersistence,
        player: player,
      ),
      toasts: ToastController(),
    );
  }

  MusicLibrary._({
    required this.catalog,
    required this.scanner,
    required this.playback,
    required this.toasts,
  }) {
    // forwarding keeps consumer<musiclibrary> working during the decomposition
    for (final controller in _children) {
      controller.addListener(_forwardChange);
    }
    unawaited(hydrate());
  }

  Iterable<ChangeNotifier> get _children => [
    catalog,
    scanner,
    playback,
    toasts,
  ];

  UnmodifiableListView<String> get directories => scanner.directories;
  UnmodifiableListView<SongViewData> get songs => catalog.songs;
  UnmodifiableListView<AlbumViewData> get albums => catalog.albums;
  UnmodifiableListView<ArtistViewData> get artists => catalog.artists;
  UnmodifiableListView<PlaylistViewData> get playlists => catalog.playlists;
  UnmodifiableListView<PinnedItemData> get pinnedItems => catalog.pinnedItems;
  List<SongViewData> get queue => playback.queue;
  int get totalSongs => catalog.totalSongs;
  int get totalAlbums => catalog.totalAlbums;
  int get totalArtists => catalog.totalArtists;
  int get totalPlaylists => catalog.totalPlaylists;
  bool get isScanning => scanner.isScanning;
  bool get usesSandboxMusicFolder => scanner.usesSandboxMusicFolder;
  String get musicDir => scanner.musicDirectory;
  bool get isPlaying => playback.isPlaying;
  bool get isFinished => playback.isFinished;
  bool get isScrubbing => playback.isScrubbing;
  bool get loopOne => playback.loopOne;
  bool get loopQueue => playback.loopQueue;
  bool get canPlayPrevious => playback.canPlayPrevious;
  SongViewData? get currentSong => playback.currentSong;
  Duration? get playerDuration => playback.duration;
  Duration? get playerPosition => playback.position;
  double get volume => playback.volume;
  String? get toastMessage => toasts.message;

  Future<void> hydrate() async {
    await scanner.hydrate();
    await playback.hydrate();
    await catalog.hydrate();
    playback.reconcile(catalog.songs);
  }

  void _forwardChange() => notifyListeners();

  String artistsDisplay(SongViewData song) {
    if (song.featuredArtists.isEmpty) return song.primaryArtist;
    return '${song.primaryArtist} feat. ${song.featuredArtists.join(', ')}';
  }

  bool isLiked(String songId) => catalog.isLiked(songId);
  bool isPinned({required String id, required QuickPlayKind kind}) =>
      catalog.isPinned(id, kind);
  Future<void> pinItem({required String id, required QuickPlayKind kind}) =>
      catalog.pin(id, kind);
  Future<void> unpinItem({required String id, required QuickPlayKind kind}) =>
      catalog.unpin(id, kind);
  Future<void> movePinnedItem(int from, int to) => catalog.movePin(from, to);

  Future<List<SongViewData>> fetchAlbumSongs(String id) =>
      catalog.fetchAlbumSongs(id);
  Future<List<SongViewData>> fetchPlaylistSongs(String id) =>
      catalog.fetchPlaylistSongs(id);
  Future<List<AlbumViewData>> fetchArtistAlbums(String id) =>
      catalog.fetchArtistAlbums(id);
  Future<List<AlbumViewData>> fetchArtistFeaturedAlbums(String id) =>
      catalog.fetchFeaturedAlbums(id);
  Future<List<SongViewData>> fetchArtistFeaturedSongs(String id) =>
      catalog.fetchFeaturedSongs(id);
  Future<List<SongViewData>> fetchRecentlyPlayed({int limit = 50}) =>
      playback.recentlyPlayed(limit: limit);
  Future<List<SongViewData>> searchSongs(String query, {int limit = 200}) =>
      catalog.searchSongs(query, limit: limit);
  Future<List<AlbumViewData>> searchAlbums(String query, {int limit = 200}) =>
      catalog.searchAlbums(query, limit: limit);
  Future<List<ArtistViewData>> searchArtists(String query, {int limit = 200}) =>
      catalog.searchArtists(query, limit: limit);
  Future<List<PlaylistViewData>> searchPlaylists(
    String query, {
    int limit = 200,
  }) => catalog.searchPlaylists(query, limit: limit);
  Future<OmniSearchResults> searchOmni(String query, {int perTypeLimit = 8}) =>
      catalog.searchOmni(query, limit: perTypeLimit);

  Future<String> createPlaylist(String name) => catalog.createPlaylist(name);
  Future<void> deletePlaylist(String id) => catalog.deletePlaylist(id);

  Future<void> addSongToPlaylist(String playlistId, SongViewData song) async {
    await catalog.addSongToPlaylist(playlistId, song.id);
    final name = catalog.playlists
        .where((playlist) => playlist.id == playlistId)
        .map((playlist) => playlist.name)
        .firstOrNull;
    showToast('${song.title} added to ${name ?? 'playlist'}');
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) =>
      catalog.removeSongFromPlaylist(playlistId, songId);

  Future<void> toggleLiked(SongViewData song) async {
    final added = await catalog.toggleLiked(song.id);
    if (added) showToast('${song.title} added to Liked Songs');
  }

  Future<SongViewData> updateSong(SongEditRequest request) async {
    final updated = await _runMetadataEdit({
      request.songId,
    }, () => catalog.updateSong(request));
    showToast('song updated');
    return updated;
  }

  Future<SongViewData> importExtractedSong(
    ExtractedSongImportRequest request,
  ) async {
    final imported = await catalog.importExtractedSong(request);
    playback.reconcile(catalog.songs);
    showToast('imported ${imported.title}');
    return imported;
  }

  Future<AlbumViewData> updateAlbum(AlbumEditRequest request) async {
    final affected = catalog.songs
        .where((song) => song.albumId == request.albumId)
        .map((song) => song.id)
        .toSet();
    final updated = await _runMetadataEdit(
      affected,
      () => catalog.updateAlbum(request),
    );
    showToast('album updated');
    return updated;
  }

  Future<T> _runMetadataEdit<T>(
    Set<String> affectedIds,
    Future<T> Function() operation,
  ) async {
    final release = await playback.releaseForEdit(affectedIds);
    // rust rewrites audio files, so the active player must release its handle
    try {
      final result = await operation();
      playback.reconcile(catalog.songs);
      if (release != null) {
        await playback.restoreAfterEdit(release, catalog.songs);
      }
      return result;
    } catch (error, stack) {
      await catalog.reloadAll();
      playback.reconcile(catalog.songs);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<ArtistViewData> updateArtistImage(
    String artistId,
    CoverArtEdit cover,
  ) async {
    final updated = await catalog.updateArtistImage(artistId, cover);
    showToast('artist image updated');
    return updated;
  }

  Future<PlaylistViewData> updatePlaylist(PlaylistEditRequest request) async {
    final updated = await catalog.updatePlaylist(request);
    showToast('playlist updated');
    return updated;
  }

  Future<void> addDirectory(String directory) async {
    try {
      await scanner.add(directory);
      showToast('scanned $directory');
    } catch (error) {
      Log.e('scan failed for $directory', error);
      showToast('scan failed');
    }
  }

  Future<void> setScanDirectory(String directory) async {
    await scanner.setOnly(directory);
    await playback.removeMissingSongs(catalog.songs);
  }

  Future<void> rescanDirectory(String directory) async {
    try {
      final added = await scanner.rescan(directory);
      showToast(
        added <= 0
            ? 'no new songs in $directory'
            : 'added $added song${added == 1 ? '' : 's'} from $directory',
      );
    } catch (error) {
      Log.e('rescan failed for $directory', error);
      showToast('rescan failed');
    }
  }

  Future<void> removeDirectory(String directory) async {
    try {
      final removed = await scanner.remove(directory);
      await playback.removeMissingSongs(catalog.songs);
      showToast(
        removed == 0
            ? 'removed $directory'
            : 'removed $removed song${removed == 1 ? '' : 's'} from $directory',
      );
    } catch (error) {
      Log.e('delete path failed for $directory', error);
    }
  }

  Future<void> resetLibrary() async {
    await playback.reset();
    await scanner.reset();
  }

  Future<void> deleteSong(String id) async {
    try {
      await catalog.deleteSong(id);
      await playback.removeSongs({id});
    } catch (error) {
      Log.e('delete song $id', error);
    }
  }

  Future<void> deleteAlbum(String albumId) async {
    final ids = (await catalog.fetchAlbumSongs(
      albumId,
    )).map((song) => song.id).toSet();
    try {
      await catalog.deleteAlbum(albumId);
      await playback.removeSongs(ids);
    } catch (error) {
      Log.e('delete album $albumId', error);
    }
  }

  Future<void> chooseOrScanMusicFolder() async {
    final directory = await scanner.chooseDirectory();
    if (directory == null) {
      showToast('folder picker unavailable');
      return;
    }
    await setScanDirectory(directory);
  }

  Future<void> onPlaySong(String id) =>
      playback.playSongById(id, catalog.songs);
  Future<void> playSongsFromStart(List<SongViewData> songs) =>
      playback.playSongsFromStart(songs);
  Future<void> playNext() => playback.playNext();
  Future<void> playPrevious() => playback.playPrevious();
  Future<void> togglePlay() => playback.togglePlay();
  void pause() => unawaited(playback.pause());
  void resume() => unawaited(playback.resume());
  Future<void> setVolume(double value) => playback.setVolume(value);
  Future<void> toggleLoopOne() => playback.toggleLoopOne();
  void toggleLoopQueue() => playback.toggleLoopQueue();
  void setPlayerPosition(double value) => playback.setPosition(value);
  void startScrub() => unawaited(playback.startScrub());
  void endScrub() => unawaited(playback.endScrub());

  void queueSong(SongViewData song) {
    playback.addToQueue(song);
    showToast('${song.title} added to queue');
  }

  void queueSongs(List<SongViewData> songs, {required String label}) {
    if (songs.isEmpty) {
      showToast('$label has no songs');
      return;
    }
    playback.addAllToQueue(songs);
    showToast(
      'added ${songs.length} ${songs.length == 1 ? 'song' : 'songs'} to queue',
    );
  }

  void queueSongNext(SongViewData song) {
    playback.playNextInQueue(song);
    showToast('${song.title} queued next');
  }

  void moveQueueItem(int from, int to) => playback.moveQueueItem(from, to);
  void removeFromQueue(int index) => playback.removeQueueItem(index);
  void clearQueue() => playback.clearQueue();
  void loopSong() {}
  void showToast(String message) => toasts.show(message);

  @override
  void dispose() {
    for (final controller in _children) {
      controller.removeListener(_forwardChange);
      controller.dispose();
    }
    super.dispose();
  }
}

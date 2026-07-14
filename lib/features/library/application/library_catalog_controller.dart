import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/shared/services/log.dart';

/// owns the cached library view used by widgets.
///
/// rust is still the source of truth. after a mutation we reload the affected
/// cache and then notify listeners so provider can rebuild consumers.
class LibraryCatalogController extends ChangeNotifier {
  final LibraryCatalogRepository repository;

  LibraryCatalogController(this.repository);

  List<SongViewData> _songs = const [];
  List<AlbumViewData> _albums = const [];
  List<ArtistViewData> _artists = const [];
  List<PlaylistViewData> _playlists = const [];
  List<PinnedItemData> _pinnedItems = const [];
  Set<String> _likedSongIds = const {};
  String? _likedPlaylistId;

  int get totalSongs => _songs.length;
  int get totalAlbums => _albums.length;
  int get totalArtists => _artists.length;
  int get totalPlaylists => _playlists.length;
  UnmodifiableListView<SongViewData> get songs => UnmodifiableListView(_songs);
  UnmodifiableListView<AlbumViewData> get albums =>
      UnmodifiableListView(_albums);
  UnmodifiableListView<ArtistViewData> get artists =>
      UnmodifiableListView(_artists);
  UnmodifiableListView<PlaylistViewData> get playlists =>
      UnmodifiableListView(_playlists);
  UnmodifiableListView<PinnedItemData> get pinnedItems =>
      UnmodifiableListView(_pinnedItems);

  bool isLiked(String songId) => _likedSongIds.contains(songId);

  Future<void> hydrate() async {
    // these reads do not depend on each other, so waiting in parallel is safe
    await Future.wait([reloadPins(), reloadAll()]);
  }

  Future<void> reloadAll() async {
    final songTotal = repository.getTotalSongs();
    final albumTotal = repository.getTotalAlbums();
    final artistTotal = repository.getTotalArtists();
    final results = await Future.wait<Object>([
      if (songTotal == 0)
        Future.value(<SongViewData>[])
      else
        repository.getSongs(0, songTotal),
      if (albumTotal == 0)
        Future.value(<AlbumViewData>[])
      else
        repository.getAlbums(0, albumTotal),
      if (artistTotal == 0)
        Future.value(<ArtistViewData>[])
      else
        repository.getArtists(0, artistTotal),
    ]);
    _songs = results[0] as List<SongViewData>;
    _albums = results[1] as List<AlbumViewData>;
    _artists = results[2] as List<ArtistViewData>;
    await reloadPlaylists(notify: false);
    notifyListeners();
  }

  Future<void> reloadPlaylists({bool notify = true}) async {
    final total = repository.getTotalPlaylists();
    final results = await Future.wait<Object?>([
      if (total == 0)
        Future.value(<PlaylistViewData>[])
      else
        repository.getPlaylists(0, total),
      repository.getLikedPlaylistId(),
      repository.getLikedSongIds(),
    ]);
    _playlists = results[0] as List<PlaylistViewData>;
    _likedPlaylistId = results[1] as String?;
    _likedSongIds = (results[2] as List<String>).toSet();
    if (notify) notifyListeners();
  }

  Future<void> reloadPins() async {
    try {
      _pinnedItems = await repository.getPinnedItems();
    } catch (error) {
      Log.e('reload pins failed', error);
      _pinnedItems = const [];
    }
    notifyListeners();
  }

  String kindName(QuickPlayKind kind) => switch (kind) {
    QuickPlayKind.song => 'song',
    QuickPlayKind.album => 'album',
    QuickPlayKind.playlist => 'playlist',
  };

  bool isPinned(String id, QuickPlayKind kind) {
    final name = kindName(kind);
    return _pinnedItems.any((item) => item.itemId == id && item.kind == name);
  }

  Future<void> pin(String id, QuickPlayKind kind) async {
    final name = kindName(kind);
    try {
      await repository.pinItem(id, name);
      await reloadPins();
    } catch (error) {
      Log.e('pin item $id ($name)', error);
    }
  }

  Future<void> unpin(String id, QuickPlayKind kind) async {
    final name = kindName(kind);
    try {
      await repository.unpinItem(id, name);
      await reloadPins();
    } catch (error) {
      Log.e('unpin item $id ($name)', error);
    }
  }

  Future<void> movePin(int from, int to) async {
    if (from < 0 ||
        from >= _pinnedItems.length ||
        to < 0 ||
        to >= _pinnedItems.length) {
      return;
    }
    final pins = List<PinnedItemData>.from(_pinnedItems);
    final item = pins.removeAt(from);
    pins.insert(to, item);
    _pinnedItems = pins;
    // update immediately so dragging feels responsive, then confirm with rust
    notifyListeners();
    try {
      await repository.movePinnedItem(item.itemId, item.kind, to);
    } catch (error) {
      Log.e('move pinned item $from -> $to', error);
    } finally {
      await reloadPins();
    }
  }

  Future<List<SongViewData>> fetchAlbumSongs(String id) =>
      repository.getAlbumSongs(id);
  Future<List<SongViewData>> fetchPlaylistSongs(String id) =>
      repository.getPlaylistSongs(id);
  Future<List<AlbumViewData>> fetchArtistAlbums(String id) =>
      repository.getArtistAlbums(id);
  Future<List<AlbumViewData>> fetchFeaturedAlbums(String id) =>
      repository.getFeaturedAlbums(id);
  Future<List<SongViewData>> fetchFeaturedSongs(String id) =>
      repository.getFeaturedSongs(id);

  Future<List<SongViewData>> searchSongs(String raw, {int limit = 200}) {
    final query = raw.trim();
    return query.isEmpty
        ? Future.value(_songs)
        : repository.searchSongs(query, limit);
  }

  Future<List<AlbumViewData>> searchAlbums(String raw, {int limit = 200}) {
    final query = raw.trim();
    return query.isEmpty
        ? Future.value(_albums)
        : repository.searchAlbums(query, limit);
  }

  Future<List<ArtistViewData>> searchArtists(String raw, {int limit = 200}) {
    final query = raw.trim();
    return query.isEmpty
        ? Future.value(_artists)
        : repository.searchArtists(query, limit);
  }

  Future<List<PlaylistViewData>> searchPlaylists(
    String raw, {
    int limit = 200,
  }) {
    final query = raw.trim();
    return query.isEmpty
        ? Future.value(_playlists)
        : repository.searchPlaylists(query, limit);
  }

  Future<OmniSearchResults> searchOmni(String raw, {int limit = 8}) async {
    final query = raw.trim();
    if (query.isEmpty) {
      return const OmniSearchResults(songs: [], albums: [], playlists: []);
    }
    final results = await Future.wait<Object>([
      searchSongs(query, limit: limit),
      searchAlbums(query, limit: limit),
      searchPlaylists(query, limit: limit),
    ]);
    return OmniSearchResults(
      songs: results[0] as List<SongViewData>,
      albums: results[1] as List<AlbumViewData>,
      playlists: results[2] as List<PlaylistViewData>,
    );
  }

  Future<String> createPlaylist(String name) async {
    final id = await repository.createPlaylist(name);
    await reloadPlaylists();
    return id;
  }

  Future<void> deletePlaylist(String id) async {
    await repository.deletePlaylist(id);
    await reloadPlaylists();
  }

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    await repository.addSongToPlaylist(playlistId, songId);
    await reloadPlaylists();
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    await repository.removeSongFromPlaylist(playlistId, songId);
    await reloadPlaylists();
  }

  Future<bool> toggleLiked(String songId) async {
    final playlistId = _likedPlaylistId;
    if (playlistId == null) return false;
    final added = !_likedSongIds.contains(songId);
    if (added) {
      await repository.addSongToPlaylist(playlistId, songId);
      _likedSongIds.add(songId);
    } else {
      await repository.removeSongFromPlaylist(playlistId, songId);
      _likedSongIds.remove(songId);
    }
    notifyListeners();
    await reloadPlaylists();
    return added;
  }

  Future<SongViewData> updateSong(SongEditRequest request) async {
    final updated = await repository.updateSong(request);
    await reloadAll();
    return _songs.firstWhere((song) => song.id == updated.id);
  }

  Future<SongViewData> importExtractedSong(
    ExtractedSongImportRequest request,
  ) async {
    final imported = await repository.importExtractedSong(request);
    await reloadAll();
    return _songs.firstWhere((song) => song.id == imported.id);
  }

  Future<AlbumViewData> updateAlbum(AlbumEditRequest request) async {
    final updated = await repository.updateAlbum(request);
    await reloadAll();
    return _albums.firstWhere((album) => album.id == updated.id);
  }

  Future<ArtistViewData> updateArtistImage(
    String id,
    CoverArtEdit cover,
  ) async {
    final updated = await repository.updateArtistImage(id, cover);
    await reloadAll();
    return _artists.firstWhere((artist) => artist.id == updated.id);
  }

  Future<PlaylistViewData> updatePlaylist(PlaylistEditRequest request) async {
    final updated = await repository.updatePlaylist(request);
    await reloadPlaylists();
    return _playlists.firstWhere((playlist) => playlist.id == updated.id);
  }

  Future<void> deleteSong(String id) async {
    await repository.deleteSong(id);
    await reloadAll();
  }

  Future<void> deleteAlbum(String id) async {
    await repository.deleteAlbum(id);
    await reloadAll();
  }
}

import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/src/rust/api/library.dart';

// controllers use this contract instead of knowing how frb names arguments
abstract interface class LibraryCatalogRepository {
  int getTotalSongs();
  int getTotalAlbums();
  int getTotalArtists();
  int getTotalPlaylists();
  Future<List<SongViewData>> getSongs(int offset, int limit);
  Future<List<AlbumViewData>> getAlbums(int offset, int limit);
  Future<List<ArtistViewData>> getArtists(int offset, int limit);
  Future<List<PlaylistViewData>> getPlaylists(int offset, int limit);
  Future<ArtworkEditData?> getArtworkEdit(ArtworkOwner owner, String ownerId);
  Future<List<String>> getScanPaths();
  Future<List<PinnedItemData>> getPinnedItems();
  Future<String?> getLikedPlaylistId();
  Future<List<String>> getLikedSongIds();
  Future<List<SongViewData>> getAlbumSongs(String albumId);
  Future<List<SongViewData>> getPlaylistSongs(String playlistId);
  Future<List<AlbumViewData>> getArtistAlbums(String artistId);
  Future<List<AlbumViewData>> getFeaturedAlbums(String artistId);
  Future<List<SongViewData>> getFeaturedSongs(String artistId);
  Future<List<SongViewData>> searchSongs(String query, int limit);
  Future<List<AlbumViewData>> searchAlbums(String query, int limit);
  Future<List<ArtistViewData>> searchArtists(String query, int limit);
  Future<List<PlaylistViewData>> searchPlaylists(String query, int limit);
  Future<String> createPlaylist(String name);
  Future<void> deletePlaylist(String id);
  Future<void> addSongToPlaylist(String playlistId, String songId);
  Future<void> removeSongFromPlaylist(String playlistId, String songId);
  Future<SongViewData> updateSong(SongEditRequest request);
  Future<SongViewData> importExtractedSong(ExtractedSongImportRequest request);
  Future<AlbumViewData> updateAlbum(AlbumEditRequest request);
  Future<ArtistViewData> updateArtistImage(String artistId, CoverArtEdit cover);
  Future<PlaylistViewData> updatePlaylist(PlaylistEditRequest request);
  Future<void> pinItem(String itemId, String kind);
  Future<void> unpinItem(String itemId, String kind);
  Future<void> movePinnedItem(String itemId, String kind, int newIndex);
  Future<void> scanDirectory(String path);
  Future<int> deleteScanPath(String path);
  Future<void> deleteSong(String id);
  Future<void> deleteAlbum(String id);
  Future<void> resetLibrary();
}

abstract interface class PlaybackPersistence {
  Future<PlaybackStateData?> loadPlaybackState();
  Future<void> savePlaybackState(String? songId, int positionMs, bool loopOne);
  Future<void> recordPlay(String songId);
  Future<List<SongViewData>> getRecentlyPlayed(int limit);
}

// this class is deliberately boring: rust owns the actual library rules
class RustLibraryRepository
    implements LibraryCatalogRepository, PlaybackPersistence {
  final LibraryApi _api;

  const RustLibraryRepository(this._api);

  @override
  int getTotalSongs() => _api.getTotalSongs();
  @override
  int getTotalAlbums() => _api.getTotalAlbums();
  @override
  int getTotalArtists() => _api.getTotalArtists();
  @override
  int getTotalPlaylists() => _api.getTotalPlaylists();

  @override
  Future<List<SongViewData>> getSongs(int offset, int limit) =>
      _api.getSongsPaginated(offset: offset, limit: limit);
  @override
  Future<List<AlbumViewData>> getAlbums(int offset, int limit) =>
      _api.getAlbumsPaginated(offset: offset, limit: limit);
  @override
  Future<List<ArtistViewData>> getArtists(int offset, int limit) =>
      _api.getArtistsPaginated(offset: offset, limit: limit);
  @override
  Future<List<PlaylistViewData>> getPlaylists(int offset, int limit) =>
      _api.getPlaylistsPaginated(offset: offset, limit: limit);
  @override
  Future<ArtworkEditData?> getArtworkEdit(ArtworkOwner owner, String ownerId) =>
      _api.getArtworkEdit(owner: owner, ownerId: ownerId);
  @override
  Future<List<String>> getScanPaths() => _api.getScanPaths();
  @override
  Future<List<PinnedItemData>> getPinnedItems() => _api.getPinnedItems();
  @override
  Future<String?> getLikedPlaylistId() => _api.getLikedSongsPlaylistId();
  @override
  Future<List<String>> getLikedSongIds() => _api.getLikedSongIds();
  @override
  Future<List<SongViewData>> getAlbumSongs(String id) =>
      _api.getSongsByAlbumId(albumId: id);
  @override
  Future<List<SongViewData>> getPlaylistSongs(String id) =>
      _api.getSongsInPlaylist(playlistId: id);
  @override
  Future<List<AlbumViewData>> getArtistAlbums(String id) =>
      _api.getAlbumsByArtistId(artistId: id);
  @override
  Future<List<AlbumViewData>> getFeaturedAlbums(String id) =>
      _api.getAlbumsArtistFeaturedOn(artistId: id);
  @override
  Future<List<SongViewData>> getFeaturedSongs(String id) =>
      _api.getSongsArtistFeaturedOn(artistId: id);
  @override
  Future<List<SongViewData>> searchSongs(String query, int limit) =>
      _api.searchSongs(query: query, limit: limit);
  @override
  Future<List<AlbumViewData>> searchAlbums(String query, int limit) =>
      _api.searchAlbums(query: query, limit: limit);
  @override
  Future<List<ArtistViewData>> searchArtists(String query, int limit) =>
      _api.searchArtists(query: query, limit: limit);
  @override
  Future<List<PlaylistViewData>> searchPlaylists(String query, int limit) =>
      _api.searchPlaylists(query: query, limit: limit);
  @override
  Future<String> createPlaylist(String name) => _api.createPlaylist(name: name);
  @override
  Future<void> deletePlaylist(String id) => _api.deletePlaylist(id: id);
  @override
  Future<void> addSongToPlaylist(String playlistId, String songId) =>
      _api.addSongToPlaylist(playlistId: playlistId, songId: songId);
  @override
  Future<void> removeSongFromPlaylist(String playlistId, String songId) =>
      _api.removeSongFromPlaylist(playlistId: playlistId, songId: songId);
  @override
  Future<SongViewData> updateSong(SongEditRequest request) =>
      _api.updateSong(request: request);
  @override
  Future<SongViewData> importExtractedSong(
    ExtractedSongImportRequest request,
  ) => _api.importExtractedSong(request: request);
  @override
  Future<AlbumViewData> updateAlbum(AlbumEditRequest request) =>
      _api.updateAlbum(request: request);
  @override
  Future<ArtistViewData> updateArtistImage(String id, CoverArtEdit cover) =>
      _api.updateArtistImage(artistId: id, cover: cover);
  @override
  Future<PlaylistViewData> updatePlaylist(PlaylistEditRequest request) =>
      _api.updatePlaylist(request: request);
  @override
  Future<void> pinItem(String id, String kind) =>
      _api.pinItem(itemId: id, kind: kind);
  @override
  Future<void> unpinItem(String id, String kind) =>
      _api.unpinItem(itemId: id, kind: kind);
  @override
  Future<void> movePinnedItem(String id, String kind, int index) =>
      _api.movePinnedItem(itemId: id, kind: kind, newIndex: index);
  @override
  Future<void> scanDirectory(String path) =>
      _api.scanDirectory(path: path, config: const ScanConfig(isDeezer: true));
  @override
  Future<int> deleteScanPath(String path) => _api.deleteScanPath(path: path);
  @override
  Future<void> deleteSong(String id) => _api.deleteSong(id: id);
  @override
  Future<void> deleteAlbum(String id) => _api.deleteAlbum(id: id);
  @override
  Future<void> resetLibrary() => _api.resetLibrary();
  @override
  Future<PlaybackStateData?> loadPlaybackState() => _api.loadPlaybackState();
  @override
  Future<void> savePlaybackState(
    String? songId,
    int positionMs,
    bool loopOne,
  ) => _api.savePlaybackState(
    songId: songId,
    positionMs: positionMs,
    loopOne: loopOne,
  );
  @override
  Future<void> recordPlay(String songId) => _api.recordPlay(songId: songId);
  @override
  Future<List<SongViewData>> getRecentlyPlayed(int limit) =>
      _api.getRecentlyPlayed(limit: limit);
}

export 'package:clutter/src/rust/api/models.dart';

import 'package:clutter/src/rust/api/models.dart';

enum QuickPlayKind { song, album, playlist }

enum LibraryPage {
  songs('songs'),
  albums('albums'),
  artists('artists'),
  playlists('playlists'),
  recentlyPlayed('recently played');

  final String label;

  const LibraryPage(this.label);
}

// this groups the parallel rust searches into one value for the search ui
class OmniSearchResults {
  final List<SongViewData> songs;
  final List<AlbumViewData> albums;
  final List<PlaylistViewData> playlists;

  const OmniSearchResults({
    required this.songs,
    required this.albums,
    required this.playlists,
  });

  bool get isEmpty => songs.isEmpty && albums.isEmpty && playlists.isEmpty;
}

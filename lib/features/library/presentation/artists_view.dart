import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/shared/presentation/cover_image.dart';
import 'package:clutter/features/library/presentation/albums_view.dart';
import 'package:clutter/shared/presentation/search_sliver_app_bar.dart';
import 'package:clutter/features/library/presentation/widgets/song_delegate.dart';
import 'package:clutter/features/metadata_editor/presentation/metadata_editors.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';

class ArtistsView extends StatefulWidget {
  const ArtistsView({super.key});

  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ArtistViewData>? _results;
  ScrollController? _scrollController;

  void _resetScrollPosition() {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final q = raw.trim();
      if (q.isEmpty) {
        if (mounted) {
          _resetScrollPosition();
          setState(() => _results = null);
        }
        return;
      }
      final lib = context.read<MusicLibrary>();
      final res = await lib.searchArtists(q);
      if (mounted) {
        _resetScrollPosition();
        setState(() => _results = res);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicLibrary>(
      builder: (context, musicLibrary, _) {
        if (musicLibrary.artists.isEmpty && musicLibrary.isScanning) {
          return const Center(child: CircularProgressIndicator());
        }
        final artists = _results ?? musicLibrary.artists;
        return RememberedScrollPosition(
          id: 'library:artists',
          onControllerChanged: (controller) => _scrollController = controller,
          builder: (context, scrollController) => CustomScrollView(
            controller: scrollController,
            slivers: [
              SearchSliverAppBar(
                controller: _controller,
                hint: "search artists",
                onChanged: _onQueryChanged,
              ),
              if (artists.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      "no artists",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _ArtistTile(artist: artists[i]),
                      childCount: artists.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtistTile extends StatelessWidget {
  final ArtistViewData artist;

  const _ArtistTile({required this.artist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onLongPressStart: (_) =>
          showArtistImageEditor(context, artist, context.read<MusicLibrary>()),
      onSecondaryTapDown: (_) =>
          showArtistImageEditor(context, artist, context.read<MusicLibrary>()),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ArtistDetailView(artist: artist)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipOval(child: _ArtistCover(coverPath: artist.coverPath)),
            ),
            const SizedBox(height: 6),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              _subtitle(artist),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitle(ArtistViewData a) {
    final albums = "${a.albumCount} album${a.albumCount == 1 ? '' : 's'}";
    final songs = "${a.songCount} song${a.songCount == 1 ? '' : 's'}";
    return "$albums • $songs";
  }
}

class _ArtistCover extends StatelessWidget {
  final String? coverPath;
  final double iconSize;

  const _ArtistCover({required this.coverPath, this.iconSize = 48});

  @override
  Widget build(BuildContext context) {
    return coverImg(
      coverPath,
      120,
      cacheSize: 360,
      expand: true,
      fallback: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Icon(Icons.person, size: iconSize, color: Colors.grey),
      ),
    );
  }
}

typedef _ArtistDetailData = ({
  List<AlbumViewData> albums,
  List<AlbumViewData> featuredAlbums,
  List<SongViewData> featuredSongs,
});

List<SongViewData> songsCreditingArtist(
  ArtistViewData artist,
  Iterable<SongViewData> songs,
) {
  final artistName = artist.name.trim().toLowerCase();
  final seen = <String>{};
  final creditedSongs = <SongViewData>[];
  for (final song in songs) {
    final creditsArtist =
        song.primaryArtist.trim().toLowerCase() == artistName ||
        song.featuredArtists.any(
          (name) => name.trim().toLowerCase() == artistName,
        );
    if (creditsArtist && seen.add(song.id)) {
      creditedSongs.add(song);
    }
  }
  return creditedSongs;
}

class ArtistDetailView extends StatefulWidget {
  final ArtistViewData artist;

  const ArtistDetailView({super.key, required this.artist});

  @override
  State<ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends State<ArtistDetailView> {
  late Future<_ArtistDetailData> _future;
  late ArtistViewData _artist;

  @override
  void initState() {
    super.initState();
    _artist = widget.artist;
    _future = _load();
  }

  Future<_ArtistDetailData> _load() async {
    final lib = context.read<MusicLibrary>();
    final results = await Future.wait([
      lib.fetchArtistAlbums(widget.artist.id),
      lib.fetchArtistFeaturedAlbums(widget.artist.id),
      lib.fetchArtistFeaturedSongs(widget.artist.id),
    ]);
    return (
      albums: results[0] as List<AlbumViewData>,
      featuredAlbums: results[1] as List<AlbumViewData>,
      featuredSongs: results[2] as List<SongViewData>,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'edit artist image',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final updated = await showArtistImageEditor(
                context,
                _artist,
                context.read<MusicLibrary>(),
              );
              if (updated != null && mounted) setState(() => _artist = updated);
            },
          ),
        ],
        shape: Border(
          bottom: BorderSide(
            color: theme.dividerTheme.color ?? Colors.transparent,
            width: 1.0,
          ),
        ),
      ),
      body: FutureBuilder<_ArtistDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return Consumer<MusicLibrary>(
            builder: (context, lib, _) {
              final songs = songsCreditingArtist(_artist, lib.songs);
              return RememberedScrollPosition(
                id: 'artist:${_artist.id}',
                builder: (context, scrollController) => CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Header(
                        artist: _artist,
                        songs: songs,
                        musicLibrary: lib,
                      ),
                    ),
                    if (data.albums.isNotEmpty) ...[
                      const _SectionHeader(title: "Albums"),
                      SliverToBoxAdapter(
                        child: _AlbumCarousel(albums: data.albums),
                      ),
                    ],
                    if (data.featuredAlbums.isNotEmpty) ...[
                      const _SectionHeader(title: "Featured on"),
                      SliverToBoxAdapter(
                        child: _AlbumCarousel(albums: data.featuredAlbums),
                      ),
                    ],
                    if (data.featuredSongs.isNotEmpty) ...[
                      const _SectionHeader(title: "Featured songs"),
                      SliverList.separated(
                        itemCount: data.featuredSongs.length,
                        itemBuilder: (context, i) => SongDelegate(
                          song: data.featuredSongs[i],
                          musicLibrary: lib,
                        ),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ArtistViewData artist;
  final List<SongViewData> songs;
  final MusicLibrary musicLibrary;

  const _Header({
    required this.artist,
    required this.songs,
    required this.musicLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: ClipOval(
              child: _ArtistCover(coverPath: artist.coverPath, iconSize: 56),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  artist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${artist.albumCount} album${artist.albumCount == 1 ? '' : 's'} • "
                  "${artist.songCount} song${artist.songCount == 1 ? '' : 's'}",
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 6),
                ArtistPlaybackActions(
                  onPlayNow: songs.isEmpty
                      ? null
                      : () => musicLibrary.playSongsFromStart(songs),
                  onQueue: songs.isEmpty
                      ? null
                      : () =>
                            musicLibrary.queueSongs(songs, label: artist.name),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ArtistPlaybackActions extends StatelessWidget {
  final VoidCallback? onPlayNow;
  final VoidCallback? onQueue;

  const ArtistPlaybackActions({
    super.key,
    required this.onPlayNow,
    required this.onQueue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: "play now",
          onPressed: onPlayNow,
          icon: Icon(
            Icons.play_arrow_rounded,
            size: 26,
            color: theme.colorScheme.onSurface.withValues(
              alpha: onPlayNow == null ? 0.3 : 0.85,
            ),
          ),
          style: _buttonStyle(theme),
        ),
        const SizedBox(width: 2),
        IconButton(
          tooltip: "add to queue",
          onPressed: onQueue,
          icon: Icon(
            Icons.playlist_add_rounded,
            size: 24,
            color: theme.colorScheme.onSurface.withValues(
              alpha: onQueue == null ? 0.3 : 0.85,
            ),
          ),
          style: _buttonStyle(theme),
        ),
      ],
    );
  }

  ButtonStyle _buttonStyle(ThemeData theme) => IconButton.styleFrom(
    backgroundColor: Colors.transparent,
    foregroundColor: theme.colorScheme.onSurface,
    disabledForegroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.3),
    padding: const EdgeInsets.all(6),
    minimumSize: const Size(36, 36),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _AlbumCarousel extends StatelessWidget {
  final List<AlbumViewData> albums;

  const _AlbumCarousel({required this.albums});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _CarouselAlbumTile(album: albums[i]),
      ),
    );
  }
}

class _CarouselAlbumTile extends StatelessWidget {
  final AlbumViewData album;

  const _CarouselAlbumTile({required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlbumDetailView(album: album)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _AlbumCoverThumb(coverPath: album.coverPath),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              album.artists.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumCoverThumb extends StatelessWidget {
  final String? coverPath;

  const _AlbumCoverThumb({required this.coverPath});

  @override
  Widget build(BuildContext context) {
    return coverImg(
      coverPath,
      72,
      cacheSize: 280,
      expand: true,
      fallback: Container(
        color: Theme.of(context).colorScheme.surface,
        child: const Icon(Icons.album, size: 36, color: Colors.grey),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/widgets/confirm_dialog.dart';
import 'package:clutter/ui/widgets/collection_context_menu.dart';
import 'package:clutter/ui/widgets/search_sliver_app_bar.dart';
import 'package:clutter/ui/widgets/song_delegate.dart';

class AlbumsView extends StatefulWidget {
  const AlbumsView({super.key});

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<AlbumViewData>? _results;

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final q = raw.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _results = null);
        return;
      }
      final lib = context.read<MusicLibrary>();
      final res = await lib.searchAlbums(q);
      if (mounted) setState(() => _results = res);
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
        if (musicLibrary.albums.isEmpty && musicLibrary.isScanning) {
          return const Center(child: CircularProgressIndicator());
        }
        final albums = _results ?? musicLibrary.albums;
        return CustomScrollView(
          slivers: [
            SearchSliverAppBar(
              controller: _controller,
              hint: "search albums",
              onChanged: _onQueryChanged,
            ),
            if (albums.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    "no albums",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _AlbumTile(
                      album: albums[i],
                      musicLibrary: musicLibrary,
                    ),
                    childCount: albums.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final AlbumViewData album;
  final MusicLibrary musicLibrary;

  const _AlbumTile({required this.album, required this.musicLibrary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onLongPressStart: (details) => showAlbumContextMenu(
        context,
        globalPosition: details.globalPosition,
        album: album,
        musicLibrary: musicLibrary,
      ),
      onSecondaryTapDown: (details) => showAlbumContextMenu(
        context,
        globalPosition: details.globalPosition,
        album: album,
        musicLibrary: musicLibrary,
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlbumDetailView(album: album)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _AlbumCover(coverPath: album.coverPath),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              album.artist,
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

class _AlbumCover extends StatelessWidget {
  final String? coverPath;

  const _AlbumCover({required this.coverPath});

  @override
  Widget build(BuildContext context) {
    if (coverPath == null) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        child: const Icon(Icons.album, size: 48, color: Colors.grey),
      );
    }
    return Image.file(
      File(coverPath!),
      fit: BoxFit.cover,
      cacheWidth: 360,
      cacheHeight: 360,
    );
  }
}

class AlbumDetailView extends StatelessWidget {
  final AlbumViewData album;

  const AlbumDetailView({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicLibrary = context.read<MusicLibrary>();
    return Scaffold(
      appBar: AppBar(
        title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        shape: Border(
          bottom: BorderSide(
            color: theme.dividerTheme.color ?? Colors.transparent,
            width: 1.0,
          ),
        ),
        actions: [
          Consumer<MusicLibrary>(
            builder: (context, lib, _) {
              final pinned = lib.isPinned(
                id: album.id,
                kind: QuickPlayKind.album,
              );
              return IconButton(
                tooltip: pinned ? "Unpin from quick play" : "Pin to quick play",
                icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                onPressed: () async {
                  if (pinned) {
                    await lib.unpinItem(
                      id: album.id,
                      kind: QuickPlayKind.album,
                    );
                  } else {
                    await lib.pinItem(id: album.id, kind: QuickPlayKind.album);
                  }
                },
              );
            },
          ),
          IconButton(
            tooltip: "Delete album",
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              final ok = await confirmDestructive(
                context,
                title: "Delete album",
                message:
                    "Remove \"${album.title}\" and all ${album.songCount} song${album.songCount == 1 ? '' : 's'} from the library? Files on disk will not be deleted.",
                actionLabel: "Delete",
              );
              if (!ok) return;
              await musicLibrary.deleteAlbum(album.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<SongViewData>>(
        future: musicLibrary.fetchAlbumSongs(album.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final songs = snapshot.data!;
          return Consumer<MusicLibrary>(
            builder: (context, lib, _) => ListView.separated(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: songs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _AlbumHeader(
                    album: album,
                    songs: songs,
                    musicLibrary: lib,
                  );
                }
                return SongDelegate(song: songs[index - 1], musicLibrary: lib);
              },
              separatorBuilder: (context, index) =>
                  index == 0 ? const SizedBox.shrink() : const Divider(),
            ),
          );
        },
      ),
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  final AlbumViewData album;
  final List<SongViewData> songs;
  final MusicLibrary musicLibrary;

  const _AlbumHeader({
    required this.album,
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _AlbumCover(coverPath: album.coverPath),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  album.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${album.songCount} ${album.songCount == 1 ? 'song' : 'songs'}",
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () => musicLibrary.playSongsFromStart(songs),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text("Play now"),
                    ),
                    OutlinedButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () => musicLibrary.queueSongs(
                              songs,
                              label: album.title,
                            ),
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: const Text("Add to queue"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

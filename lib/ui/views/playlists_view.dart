import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/widgets/collection_context_menu.dart';
import 'package:clutter/ui/widgets/search_sliver_app_bar.dart';
import 'package:clutter/ui/widgets/song_delegate.dart';

class PlaylistsView extends StatefulWidget {
  const PlaylistsView({super.key});

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PlaylistViewData>? _results;

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final q = raw.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _results = null);
        return;
      }
      final lib = context.read<MusicLibrary>();
      final res = await lib.searchPlaylists(q);
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
        final playlists = _results ?? musicLibrary.playlists;
        return CustomScrollView(
          slivers: [
            SearchSliverAppBar(
              controller: _controller,
              hint: "search playlists",
              onChanged: _onQueryChanged,
            ),
            if (playlists.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    "no playlists",
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
                    (context, i) => _PlaylistTile(
                      playlist: playlists[i],
                      musicLibrary: musicLibrary,
                    ),
                    childCount: playlists.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final PlaylistViewData playlist;
  final MusicLibrary musicLibrary;

  const _PlaylistTile({required this.playlist, required this.musicLibrary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onLongPressStart: (details) => showPlaylistContextMenu(
        context,
        globalPosition: details.globalPosition,
        playlist: playlist,
        musicLibrary: musicLibrary,
      ),
      onSecondaryTapDown: (details) => showPlaylistContextMenu(
        context,
        globalPosition: details.globalPosition,
        playlist: playlist,
        musicLibrary: musicLibrary,
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlaylistDetailView(playlist: playlist),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _PlaylistCover(playlist: playlist),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              "${playlist.songCount} songs",
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

class _PlaylistCover extends StatelessWidget {
  final PlaylistViewData playlist;

  const _PlaylistCover({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (playlist.isSystem) {
      return Container(
        color: theme.colorScheme.surface,
        child: const Icon(Icons.favorite, color: Colors.redAccent, size: 56),
      );
    }
    final initials = _initials(playlist.name);
    return Container(
      color: theme.colorScheme.surface,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r"\s+")).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return "?";
    final first = parts.first.characters.firstOrNull ?? '';
    if (parts.length == 1) return first.toUpperCase();
    final second = parts.elementAt(1).characters.firstOrNull ?? '';
    return (first + second).toUpperCase();
  }
}

class PlaylistDetailView extends StatelessWidget {
  final PlaylistViewData playlist;

  const PlaylistDetailView({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
                id: playlist.id,
                kind: QuickPlayKind.playlist,
              );
              return IconButton(
                tooltip: pinned ? "Unpin from quick play" : "Pin to quick play",
                icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                onPressed: () async {
                  if (pinned) {
                    await lib.unpinItem(
                      id: playlist.id,
                      kind: QuickPlayKind.playlist,
                    );
                  } else {
                    await lib.pinItem(
                      id: playlist.id,
                      kind: QuickPlayKind.playlist,
                    );
                  }
                },
              );
            },
          ),
          if (!playlist.isSystem)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: "delete playlist",
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("delete playlist?"),
                    content: Text(
                      "'${playlist.name}' will be removed. songs won't be deleted.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text("cancel"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text("delete"),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await context.read<MusicLibrary>().deletePlaylist(
                    playlist.id,
                  );
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
        ],
      ),
      body: Consumer<MusicLibrary>(
        builder: (context, musicLibrary, _) => FutureBuilder<List<SongViewData>>(
          // Keyed on playlist membership so add/remove actions refresh the list.
          future: musicLibrary.fetchPlaylistSongs(playlist.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final songs = snapshot.data!;
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: songs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _PlaylistHeader(
                    playlist: playlist,
                    songs: songs,
                    musicLibrary: musicLibrary,
                  );
                }
                final song = songs[index - 1];
                return SongDelegate(
                  song: song,
                  musicLibrary: musicLibrary,
                  onRemoveFromPlaylist: () =>
                      musicLibrary.removeSongFromPlaylist(playlist.id, song.id),
                );
              },
              separatorBuilder: (context, index) =>
                  index == 0 ? const SizedBox.shrink() : const Divider(),
            );
          },
        ),
      ),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final PlaylistViewData playlist;
  final List<SongViewData> songs;
  final MusicLibrary musicLibrary;

  const _PlaylistHeader({
    required this.playlist,
    required this.songs,
    required this.musicLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songCount = songs.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _PlaylistCover(playlist: playlist),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$songCount ${songCount == 1 ? 'song' : 'songs'}",
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                              label: playlist.name,
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

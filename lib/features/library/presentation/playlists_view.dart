import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/library/presentation/widgets/collection_context_menu.dart';
import 'package:clutter/shared/presentation/search_sliver_app_bar.dart';
import 'package:clutter/features/library/presentation/widgets/song_delegate.dart';
import 'package:clutter/features/metadata_editor/presentation/metadata_editors.dart';
import 'package:clutter/shared/presentation/cover_image.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';

class PlaylistsView extends StatefulWidget {
  const PlaylistsView({super.key});

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PlaylistViewData>? _results;
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
      final res = await lib.searchPlaylists(q);
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
        final playlists = _results ?? musicLibrary.playlists;
        return RememberedScrollPosition(
          id: 'library:playlists',
          onControllerChanged: (controller) => _scrollController = controller,
          builder: (context, scrollController) => CustomScrollView(
            controller: scrollController,
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
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
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
          ),
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
    if (playlist.imagePath != null) {
      return coverImg(playlist.imagePath, 120, cacheSize: 360, expand: true);
    }
    final icon = playlistIcons[playlist.iconKey];
    if (icon != null) {
      return Container(
        color: theme.colorScheme.surface,
        alignment: Alignment.center,
        child: Icon(icon, size: 56),
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
          if (!playlist.isSystem)
            IconButton(
              tooltip: "edit playlist",
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final updated = await showPlaylistEditor(
                  context,
                  playlist,
                  context.read<MusicLibrary>(),
                );
                if (updated != null && context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailView(playlist: updated),
                    ),
                  );
                }
              },
            ),
          Consumer<MusicLibrary>(
            builder: (context, lib, _) {
              final pinned = lib.isPinned(
                id: playlist.id,
                kind: QuickPlayKind.playlist,
              );
              return IconButton(
                tooltip: pinned ? "unpin from quick play" : "pin to quick play",
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
          // keyed on playlist membership so add/remove actions refresh the list.
          future: musicLibrary.fetchPlaylistSongs(playlist.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final songs = snapshot.data!;
            return RememberedScrollPosition(
              id: 'playlist:${playlist.id}',
              builder: (context, scrollController) => ListView.separated(
                controller: scrollController,
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
                    onRemoveFromPlaylist: () => musicLibrary
                        .removeSongFromPlaylist(playlist.id, song.id),
                  );
                },
                separatorBuilder: (context, index) =>
                    index == 0 ? const SizedBox.shrink() : const Divider(),
              ),
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
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      tooltip: "play now",
                      onPressed: songs.isEmpty
                          ? null
                          : () => musicLibrary.playSongsFromStart(songs),
                      icon: Icon(
                        Icons.play_arrow_rounded,
                        size: 26,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: songs.isEmpty ? 0.3 : 0.85,
                        ),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: theme.colorScheme.onSurface,
                        disabledForegroundColor: theme.colorScheme.onSurface
                            .withValues(alpha: 0.3),
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(36, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: "add to queue",
                      onPressed: songs.isEmpty
                          ? null
                          : () => musicLibrary.queueSongs(
                              songs,
                              label: playlist.name,
                            ),
                      icon: Icon(
                        Icons.playlist_add_rounded,
                        size: 24,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: songs.isEmpty ? 0.3 : 0.85,
                        ),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: theme.colorScheme.onSurface,
                        disabledForegroundColor: theme.colorScheme.onSurface
                            .withValues(alpha: 0.3),
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(36, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
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

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/widgets/song_context_menu.dart';

class SongDelegate extends StatelessWidget {
  final SongViewData song;
  final MusicLibrary musicLibrary;
  final VoidCallback? onRemoveFromPlaylist;

  const SongDelegate({
    super.key,
    required this.song,
    required this.musicLibrary,
    this.onRemoveFromPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrentSong = musicLibrary.currentSong?.id == song.id;
    final colors = Theme.of(context).colorScheme;
    final liked = musicLibrary.isLiked(song.id);

    return Dismissible(
      key: ValueKey("song-${song.id}"),
      direction: DismissDirection.startToEnd,
      background: Container(
        color: colors.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.playlist_play, color: colors.onPrimary),
            const SizedBox(width: 8),
            Text(
              "Queue next",
              style: TextStyle(
                color: colors.onPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        musicLibrary.queueSongNext(song);
        return false;
      },
      child: GestureDetector(
        onLongPressStart: (d) => showSongContextMenu(
          context,
          globalPosition: d.globalPosition,
          song: song,
          musicLibrary: musicLibrary,
          onRemoveFromPlaylist: onRemoveFromPlaylist,
        ),
        onSecondaryTapDown: (d) => showSongContextMenu(
          context,
          globalPosition: d.globalPosition,
          song: song,
          musicLibrary: musicLibrary,
          onRemoveFromPlaylist: onRemoveFromPlaylist,
        ),
        child: InkWell(
          onTap: () => musicLibrary.onPlaySong(song.id),
          child: ListTile(
            leading: _buildCoverImg(song),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              musicLibrary.artistsDisplay(song),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: isCurrentSong
                ? const Icon(Icons.play_arrow, color: Colors.green)
                : IconButton(
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? Colors.redAccent : null,
                      size: 20,
                    ),
                    tooltip: liked ? "unlike" : "like",
                    onPressed: () => musicLibrary.toggleLiked(song),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImg(SongViewData song) {
    final coverPath = song.coverPath;
    if (coverPath == null) {
      return const SizedBox(
        width: 50,
        height: 50,
        child: Placeholder(color: Colors.red),
      );
    }
    return Image.file(
      File(coverPath),
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      cacheWidth: 150,
      cacheHeight: 150,
    );
  }
}

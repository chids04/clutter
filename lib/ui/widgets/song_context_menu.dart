import 'package:flutter/material.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/widgets/confirm_dialog.dart';

Future<void> _pickPlaylistAndAdd(
  BuildContext context,
  MusicLibrary musicLibrary,
  SongViewData song,
) async {
  final userPlaylists =
      musicLibrary.playlists.where((p) => !p.isSystem).toList();
  if (userPlaylists.isEmpty) {
    musicLibrary.showToast("no playlists yet — create one first");
    return;
  }
  final picked = await showModalBottomSheet<PlaylistViewData>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: userPlaylists.length,
        separatorBuilder: (c, i) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = userPlaylists[i];
          return ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(p.name),
            subtitle: Text("${p.songCount} songs"),
            onTap: () => Navigator.of(ctx).pop(p),
          );
        },
      ),
    ),
  );
  if (picked != null) {
    await musicLibrary.addSongToPlaylist(picked.id, song);
  }
}

Future<void> showSongContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required SongViewData song,
  required MusicLibrary musicLibrary,
  VoidCallback? onRemoveFromPlaylist,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final liked = musicLibrary.isLiked(song.id);
  final pinned = musicLibrary.isPinned(id: song.id, kind: QuickPlayKind.song);
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    ),
    items: [
      const PopupMenuItem<String>(
        value: 'queue',
        child: Row(
          children: [
            Icon(Icons.playlist_add, size: 18),
            SizedBox(width: 8),
            Text("Add to queue"),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'toggle_pin',
        child: Row(
          children: [
            Icon(
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(pinned ? "Unpin from quick play" : "Pin to quick play"),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'toggle_like',
        child: Row(
          children: [
            Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: liked ? Colors.redAccent : null,
            ),
            const SizedBox(width: 8),
            Text(liked ? "Unlike" : "Like"),
          ],
        ),
      ),
      const PopupMenuItem<String>(
        value: 'add_to_playlist',
        child: Row(
          children: [
            Icon(Icons.library_add, size: 18),
            SizedBox(width: 8),
            Text("Add to playlist…"),
          ],
        ),
      ),
      if (onRemoveFromPlaylist != null)
        const PopupMenuItem<String>(
          value: 'remove_from_playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_remove, size: 18),
              SizedBox(width: 8),
              Text("Remove from playlist"),
            ],
          ),
        ),
      const PopupMenuItem<String>(
        value: 'delete_song',
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              "Delete from library",
              style: TextStyle(color: Colors.redAccent),
            ),
          ],
        ),
      ),
    ],
  );

  if (v == 'queue') {
    musicLibrary.queueSong(song);
  } else if (v == 'toggle_pin') {
    if (pinned) {
      await musicLibrary.unpinItem(id: song.id, kind: QuickPlayKind.song);
    } else {
      await musicLibrary.pinItem(id: song.id, kind: QuickPlayKind.song);
    }
  } else if (v == 'toggle_like') {
    musicLibrary.toggleLiked(song);
  } else if (v == 'add_to_playlist') {
    if (context.mounted) await _pickPlaylistAndAdd(context, musicLibrary, song);
  } else if (v == 'remove_from_playlist') {
    onRemoveFromPlaylist?.call();
  } else if (v == 'delete_song') {
    if (!context.mounted) return;
    final ok = await confirmDestructive(
      context,
      title: "Delete song",
      message:
          "Remove \"${song.title}\" from the library? The file on disk will not be deleted.",
      actionLabel: "Delete",
    );
    if (ok) await musicLibrary.deleteSong(song.id);
  }
}

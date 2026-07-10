import 'package:flutter/material.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/widgets/metadata_editors.dart';

Future<void> _showQueueMenu(
  BuildContext context, {
  required Offset globalPosition,
  required Future<void> Function() onQueue,
  required Future<void> Function() onEdit,
  bool allowEdit = true,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final value = await showMenu<String>(
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
            Text("add to queue"),
          ],
        ),
      ),
      if (allowEdit)
        const PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text("edit…"),
            ],
          ),
        ),
    ],
  );

  if (value == 'queue') await onQueue();
  if (value == 'edit') await onEdit();
}

Future<void> showAlbumContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required AlbumViewData album,
  required MusicLibrary musicLibrary,
}) async {
  await _showQueueMenu(
    context,
    globalPosition: globalPosition,
    onQueue: () async {
      final songs = await musicLibrary.fetchAlbumSongs(album.id);
      musicLibrary.queueSongs(songs, label: album.title);
    },
    onEdit: () => showAlbumEditor(context, album, musicLibrary),
  );
}

Future<void> showPlaylistContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required PlaylistViewData playlist,
  required MusicLibrary musicLibrary,
}) async {
  await _showQueueMenu(
    context,
    globalPosition: globalPosition,
    onQueue: () async {
      final songs = await musicLibrary.fetchPlaylistSongs(playlist.id);
      musicLibrary.queueSongs(songs, label: playlist.name);
    },
    onEdit: playlist.isSystem
        ? () async {}
        : () => showPlaylistEditor(context, playlist, musicLibrary),
    allowEdit: !playlist.isSystem,
  );
}

import 'package:flutter/material.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';

Future<void> _showQueueMenu(
  BuildContext context, {
  required Offset globalPosition,
  required Future<void> Function() onQueue,
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
    items: const [
      PopupMenuItem<String>(
        value: 'queue',
        child: Row(
          children: [
            Icon(Icons.playlist_add, size: 18),
            SizedBox(width: 8),
            Text("Add to queue"),
          ],
        ),
      ),
    ],
  );

  if (value == 'queue') await onQueue();
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
  );
}

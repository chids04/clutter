import 'package:flutter/material.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/library/presentation/albums_view.dart';
import 'package:clutter/features/library/presentation/artists_view.dart';
import 'package:clutter/shared/presentation/confirm_dialog.dart';
import 'package:clutter/features/metadata_editor/presentation/metadata_editors.dart';
import 'package:clutter/shared/presentation/cover_image.dart';

class _SongContextMenuBounceCurve extends Curve {
  const _SongContextMenuBounceCurve();

  @override
  double transformInternal(double t) {
    const firstSettle = 0.72;
    const recoilEnd = 0.86;
    const recoil = 0.025;

    if (t <= firstSettle) {
      return Curves.easeOutCubic.transform(t / firstSettle);
    }
    if (t <= recoilEnd) {
      final progress = (t - firstSettle) / (recoilEnd - firstSettle);
      return 1 - (recoil * Curves.easeInOut.transform(progress));
    }

    final progress = (t - recoilEnd) / (1 - recoilEnd);
    return (1 - recoil) + (recoil * Curves.easeOut.transform(progress));
  }
}

const _songContextMenuAnimationStyle = AnimationStyle(
  curve: _SongContextMenuBounceCurve(),
  reverseCurve: Curves.easeInCubic,
  duration: Duration(milliseconds: 180),
);

AlbumViewData? _albumForSong(MusicLibrary musicLibrary, SongViewData song) {
  for (final album in musicLibrary.albums) {
    if (album.id == song.albumId) return album;
  }
  return null;
}

ArtistViewData? _leadingArtistForSong(
  MusicLibrary musicLibrary,
  SongViewData song,
) {
  for (final artist in musicLibrary.artists) {
    if (artist.name == song.primaryArtist) return artist;
  }
  return null;
}

Future<void> _pickPlaylistAndAdd(
  BuildContext context,
  MusicLibrary musicLibrary,
  SongViewData song,
) async {
  final userPlaylists = musicLibrary.playlists
      .where((p) => !p.isSystem)
      .toList();
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
            leading: p.imagePath != null
                ? coverImg(p.imagePath, 40)
                : Icon(playlistIcons[p.iconKey] ?? Icons.queue_music),
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
    popUpAnimationStyle: _songContextMenuAnimationStyle,
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
      PopupMenuItem<String>(
        value: "go_to_album",
        child: Row(
          children: [
            Icon(Icons.album, size: 18),
            SizedBox(width: 8),
            Text("go to album"),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: "go_to_artist",
        child: Row(
          children: [
            Icon(Icons.person, size: 18),
            SizedBox(width: 8),
            Text("go to artist"),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'toggle_pin',
        child: Row(
          children: [
            Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                pinned ? "unpin from quick play" : "pin to quick play",
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
            Text(liked ? "unlike" : "like"),
          ],
        ),
      ),
      const PopupMenuItem<String>(
        value: 'add_to_playlist',
        child: Row(
          children: [
            Icon(Icons.library_add, size: 18),
            SizedBox(width: 8),
            Text("add to playlist…"),
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
              Flexible(
                child: Text(
                  "remove from playlist",
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      const PopupMenuItem<String>(
        value: 'edit_song',
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 8),
            Text("edit song…"),
          ],
        ),
      ),
      const PopupMenuItem<String>(
        value: 'delete_song',
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                "delete from library",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.redAccent),
              ),
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
  } else if (v == 'edit_song') {
    if (context.mounted) await showSongEditor(context, song, musicLibrary);
  } else if (v == 'delete_song') {
    if (!context.mounted) return;
    final ok = await confirmDestructive(
      context,
      title: "delete song",
      message:
          "Remove \"${song.title}\" from the library? The file on disk will not be deleted.",
      actionLabel: "delete",
    );
    if (ok) await musicLibrary.deleteSong(song.id);
  } else if (v == "go_to_album") {
    if (!context.mounted) return;
    final album = _albumForSong(musicLibrary, song);
    if (album == null) {
      musicLibrary.showToast("album not found");
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AlbumDetailView(album: album)));
  } else if (v == "go_to_artist") {
    if (!context.mounted) return;
    final artist = _leadingArtistForSong(musicLibrary, song);
    if (artist == null) {
      musicLibrary.showToast("artist not found");
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ArtistDetailView(artist: artist)));
  }
}

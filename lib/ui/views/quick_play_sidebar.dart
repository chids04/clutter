import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';

const double _kPanelWidth = 280.0;
const double _kHandleWidth = 40.0;
const double _kHandleHeight = 80.0;
const Duration _kOpenDelay = Duration(milliseconds: 120);
const Duration _kCloseDelay = Duration(milliseconds: 250);
const Duration _kAnimationDuration = Duration(milliseconds: 220);

class QuickPlaySidebar extends StatefulWidget {
  final Widget child;

  const QuickPlaySidebar({super.key, required this.child});

  @override
  State<QuickPlaySidebar> createState() => _QuickPlaySidebarState();
}

class _QuickPlaySidebarState extends State<QuickPlaySidebar> {
  bool _isOpen = false;
  bool _isDragging = false;
  Timer? _hoverTimer;
  bool _hoveringTrigger = false;
  bool _hoveringPanel = false;

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  void _open() {
    _hoverTimer?.cancel();
    if (_isOpen) return;
    setState(() => _isOpen = true);
  }

  void _close() {
    _hoverTimer?.cancel();
    if (!_isOpen) return;
    setState(() => _isOpen = false);
  }

  void _scheduleOpen() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(_kOpenDelay, () {
      if (_hoveringTrigger || _hoveringPanel) _open();
    });
  }

  void _scheduleClose() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(_kCloseDelay, () {
      if (!_isDragging && !_hoveringTrigger && !_hoveringPanel) _close();
    });
  }

  void _onTriggerEnter(PointerEvent _) {
    _hoveringTrigger = true;
    if (_isDesktop) _scheduleOpen();
  }

  void _onTriggerExit(PointerEvent _) {
    _hoveringTrigger = false;
    if (_isDesktop) _scheduleClose();
  }

  void _onPanelEnter(PointerEvent _) {
    _hoveringPanel = true;
    if (_isDesktop) _scheduleOpen();
  }

  void _onPanelExit(PointerEvent _) {
    _hoveringPanel = false;
    if (_isDesktop) _scheduleClose();
  }

  void _onMobileLongPress(LongPressStartDetails _) => _open();

  void _onDragStart() {
    _hoverTimer?.cancel();
    if (_isDragging) return;
    setState(() => _isDragging = true);
  }

  void _onDragEnd() {
    _hoverTimer?.cancel();
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    _scheduleClose();
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          widget.child,
          if (_isOpen)
            GestureDetector(
              onTap: _close,
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
          AnimatedPositioned(
            duration: _kAnimationDuration,
            curve: Curves.easeOutCubic,
            right: _isOpen ? 0 : -_kPanelWidth,
            top: 0,
            bottom: 0,
            width: _kPanelWidth + _kHandleWidth,
            child: Row(
              children: [
                // Half-circle trigger handle attached to the panel's left edge.
                GestureDetector(
                  onTap: _isDesktop ? null : _open,
                  onLongPressStart: _onMobileLongPress,
                  child: MouseRegion(
                    onEnter: _onTriggerEnter,
                    onExit: _onTriggerExit,
                    child: Container(
                      width: _kHandleWidth,
                      height: _kHandleHeight,
                      margin: const EdgeInsets.only(
                        top: _kHandleHeight,
                        bottom: _kHandleHeight,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          left: BorderSide(
                            color:
                                Theme.of(context).dividerTheme.color ??
                                Colors.transparent,
                          ),
                          top: BorderSide(
                            color:
                                Theme.of(context).dividerTheme.color ??
                                Colors.transparent,
                          ),
                          bottom: BorderSide(
                            color:
                                Theme.of(context).dividerTheme.color ??
                                Colors.transparent,
                          ),
                        ),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(_kHandleWidth / 2),
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 3,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Main panel
                MouseRegion(
                  onEnter: _onPanelEnter,
                  onExit: _onPanelExit,
                  child: Container(
                    width: _kPanelWidth,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        left: BorderSide(
                          color:
                              Theme.of(context).dividerTheme.color ??
                              Colors.transparent,
                        ),
                      ),
                    ),
                    child: _SidebarContent(
                      onClose: _close,
                      onDragStart: _onDragStart,
                      onDragEnd: _onDragEnd,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _SidebarContent({
    required this.onClose,
    required this.onDragStart,
    required this.onDragEnd,
  });

  Future<void> _playPinned(
    BuildContext context,
    MusicLibrary lib,
    PinnedItemData pin,
  ) async {
    switch (pin.kind) {
      case 'song':
        await lib.onPlaySong(pin.itemId);
      case 'album':
        final songs = await lib.fetchAlbumSongs(pin.itemId);
        await lib.playSongsFromStart(songs);
      case 'playlist':
        final songs = await lib.fetchPlaylistSongs(pin.itemId);
        await lib.playSongsFromStart(songs);
    }
    onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<MusicLibrary>(
      builder: (context, lib, _) {
        final pins = lib.pinnedItems;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerTheme.color ?? Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "quick play",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: "close",
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),
            if (pins.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "pin songs, albums, or playlists to see them here",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: pins.length,
                  onReorderStart: (_) => onDragStart(),
                  onReorderEnd: (_) => onDragEnd(),
                  onReorder: (from, to) {
                    if (to > from) to -= 1;
                    lib.movePinnedItem(from, to);
                  },
                  itemBuilder: (context, i) => _PinnedTile(
                    key: ValueKey('pinned-${pins[i].itemId}-${pins[i].kind}'),
                    pin: pins[i],
                    musicLibrary: lib,
                    onPlay: () => _playPinned(context, lib, pins[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PinnedTile extends StatelessWidget {
  final PinnedItemData pin;
  final MusicLibrary musicLibrary;
  final VoidCallback onPlay;

  const _PinnedTile({
    super.key,
    required this.pin,
    required this.musicLibrary,
    required this.onPlay,
  });

  String _label() {
    switch (pin.kind) {
      case 'song':
        final song = musicLibrary.songs.firstWhere(
          (s) => s.id == pin.itemId,
          orElse: () => SongViewData(
            id: '',
            title: 'Unknown song',
            primaryArtist: '',
            featuredArtists: const [],
            filePath: '',
            trackNum: 0,
            discNum: 0,
            album: '',
          ),
        );
        return song.title;
      case 'album':
        final album = musicLibrary.albums.firstWhere(
          (a) => a.id == pin.itemId,
          orElse: () => AlbumViewData(
            id: '',
            title: 'Unknown album',
            artist: '',
            songCount: 0,
          ),
        );
        return album.title;
      case 'playlist':
        final playlist = musicLibrary.playlists.firstWhere(
          (p) => p.id == pin.itemId,
          orElse: () => PlaylistViewData(
            id: '',
            name: 'Unknown playlist',
            isSystem: false,
            songCount: 0,
          ),
        );
        return playlist.name;
      default:
        return 'Unknown';
    }
  }

  String _subtitle() {
    switch (pin.kind) {
      case 'song':
        final song = musicLibrary.songs.firstWhere(
          (s) => s.id == pin.itemId,
          orElse: () => SongViewData(
            id: '',
            title: '',
            primaryArtist: '',
            featuredArtists: const [],
            filePath: '',
            trackNum: 0,
            discNum: 0,
            album: '',
          ),
        );
        return song.id.isEmpty ? '' : musicLibrary.artistsDisplay(song);
      case 'album':
        final album = musicLibrary.albums.firstWhere(
          (a) => a.id == pin.itemId,
          orElse: () =>
              AlbumViewData(id: '', title: '', artist: '', songCount: 0),
        );
        return album.id.isEmpty
            ? ''
            : '${album.artist} • ${album.songCount} song${album.songCount == 1 ? '' : 's'}';
      case 'playlist':
        final playlist = musicLibrary.playlists.firstWhere(
          (p) => p.id == pin.itemId,
          orElse: () =>
              PlaylistViewData(id: '', name: '', isSystem: false, songCount: 0),
        );
        return playlist.id.isEmpty
            ? ''
            : '${playlist.songCount} song${playlist.songCount == 1 ? '' : 's'}';
      default:
        return '';
    }
  }

  Widget _leading(BuildContext context) {
    final theme = Theme.of(context);
    switch (pin.kind) {
      case 'song':
        final song = musicLibrary.songs.firstWhere(
          (s) => s.id == pin.itemId,
          orElse: () => SongViewData(
            id: '',
            title: '',
            primaryArtist: '',
            featuredArtists: const [],
            filePath: '',
            trackNum: 0,
            discNum: 0,
            album: '',
          ),
        );
        if (song.id.isEmpty) {
          return _PlaceholderIcon(theme: theme, icon: Icons.music_note);
        }
        if (song.coverPath case final path?) {
          return Image.file(
            File(path),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          );
        }
        return _PlaceholderIcon(theme: theme, icon: Icons.music_note);
      case 'album':
        final album = musicLibrary.albums.firstWhere(
          (a) => a.id == pin.itemId,
          orElse: () =>
              AlbumViewData(id: '', title: '', artist: '', songCount: 0),
        );
        if (album.id.isEmpty) {
          return _PlaceholderIcon(theme: theme, icon: Icons.album);
        }
        if (album.coverPath case final path?) {
          return Image.file(
            File(path),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          );
        }
        return _PlaceholderIcon(theme: theme, icon: Icons.album);
      case 'playlist':
        final playlist = musicLibrary.playlists.firstWhere(
          (p) => p.id == pin.itemId,
          orElse: () =>
              PlaylistViewData(id: '', name: '', isSystem: false, songCount: 0),
        );
        if (playlist.id.isEmpty) {
          return _PlaceholderIcon(theme: theme, icon: Icons.queue_music);
        }
        if (playlist.isSystem) {
          return Container(
            width: 44,
            height: 44,
            color: theme.colorScheme.surface,
            child: const Icon(Icons.favorite, color: Colors.redAccent),
          );
        }
        final initials = _initials(playlist.name);
        return Container(
          width: 44,
          height: 44,
          color: theme.colorScheme.surface,
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        );
      default:
        return _PlaceholderIcon(theme: theme, icon: Icons.queue_music);
    }
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r"\s+")).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return "?";
    final first = parts.first.characters.firstOrNull ?? '';
    if (parts.length == 1) return first.toUpperCase();
    final second = parts.elementAt(1).characters.firstOrNull ?? '';
    return (first + second).toUpperCase();
  }

  QuickPlayKind _kindFromString(String kind) {
    return switch (kind) {
      'song' => QuickPlayKind.song,
      'album' => QuickPlayKind.album,
      'playlist' => QuickPlayKind.playlist,
      _ => QuickPlayKind.song,
    };
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle();
    return ListTile(
      dense: true,
      leading: SizedBox(width: 44, height: 44, child: _leading(context)),
      title: Text(_label(), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: "unpin",
        onPressed: () => musicLibrary.unpinItem(
          id: pin.itemId,
          kind: _kindFromString(pin.kind),
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      onTap: onPlay,
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  final ThemeData theme;
  final IconData icon;

  const _PlaceholderIcon({required this.theme, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      color: theme.colorScheme.surface,
      child: Icon(icon, color: Colors.grey, size: 24),
    );
  }
}

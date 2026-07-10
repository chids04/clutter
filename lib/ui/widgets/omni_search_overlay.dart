import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/services/cover_img_loader.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/views/albums_view.dart';
import 'package:clutter/ui/views/playlists_view.dart';

Future<void> showOmniSearchOverlay({
  required BuildContext context,
  required GlobalKey<NavigatorState> libraryNavigatorKey,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (context, _, _) {
      return _OmniSearchDialog(libraryNavigatorKey: libraryNavigatorKey);
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DismissOmniSearchIntent extends Intent {
  const _DismissOmniSearchIntent();
}

class _OmniSearchDialog extends StatefulWidget {
  final GlobalKey<NavigatorState> libraryNavigatorKey;

  const _OmniSearchDialog({required this.libraryNavigatorKey});

  @override
  State<_OmniSearchDialog> createState() => _OmniSearchDialogState();
}

class _OmniSearchDialogState extends State<_OmniSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  OmniSearchResults? _results;
  bool _isLoading = false;
  String? _error;
  int _queryToken = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    final token = ++_queryToken;
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    _debounce = Timer(const Duration(milliseconds: 190), () async {
      try {
        final lib = context.read<MusicLibrary>();
        final results = await lib.searchOmni(query);
        if (!mounted || token != _queryToken) return;
        setState(() {
          _results = results;
          _isLoading = false;
        });
      } catch (_) {
        if (!mounted || token != _queryToken) return;
        setState(() {
          _error = "search failed";
          _isLoading = false;
        });
      }
    });
  }

  void _dismiss() {
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _playSong(MusicLibrary musicLibrary, SongViewData song) {
    _dismiss();
    unawaited(musicLibrary.onPlaySong(song.id));
  }

  void _openAlbum(AlbumViewData album) {
    final navigator = widget.libraryNavigatorKey.currentState;
    _dismiss();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigator?.push(
        MaterialPageRoute(builder: (_) => AlbumDetailView(album: album)),
      );
    });
  }

  void _openPlaylist(PlaylistViewData playlist) {
    final navigator = widget.libraryNavigatorKey.currentState;
    _dismiss();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigator?.push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailView(playlist: playlist),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final theme = Theme.of(context);
    final isMobile = size.width < 640;
    final horizontalInset = isMobile ? 14.0 : 24.0;
    final topInset = mediaQuery.padding.top + (isMobile ? 12.0 : 24.0);
    final bottomInset =
        mediaQuery.padding.bottom +
        mediaQuery.viewInsets.bottom +
        (isMobile ? 12.0 : 24.0);
    final maxWidth = isMobile ? size.width - (horizontalInset * 2) : 580.0;
    final availableHeight = size.height - topInset - bottomInset;
    final maxHeight = isMobile
        ? math.max(180.0, math.min(availableHeight, 560.0))
        : math.min(size.height * 0.72, 680.0);

    final resultsBody = Consumer<MusicLibrary>(
      builder: (context, musicLibrary, _) {
        final body = _ResultsBody(
          query: _controller.text.trim(),
          results: _results,
          isLoading: _isLoading,
          error: _error,
          musicLibrary: musicLibrary,
          onSongTap: (song) => _playSong(musicLibrary, song),
          onAlbumTap: _openAlbum,
          onPlaylistTap: _openPlaylist,
        );
        return Column(
          mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _SearchField(controller: _controller, onChanged: _onQueryChanged),
            Divider(
              height: 1,
              color: theme.dividerTheme.color ?? Colors.transparent,
            ),
            if (isMobile) Expanded(child: body) else Flexible(child: body),
          ],
        );
      },
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _DismissOmniSearchIntent(),
      },
      child: Actions(
        actions: {
          _DismissOmniSearchIntent: CallbackAction<_DismissOmniSearchIntent>(
            onInvoke: (_) {
              _dismiss();
              return null;
            },
          ),
        },
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            horizontalInset,
            topInset,
            horizontalInset,
            bottomInset,
          ),
          child: Align(
            alignment: isMobile ? Alignment.topCenter : Alignment.center,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: maxWidth,
                height: isMobile ? maxHeight : null,
                constraints: isMobile
                    ? null
                    : BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.dividerTheme.color ?? Colors.transparent,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 32,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: resultsBody,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        hintText: "search songs, albums, playlists",
        prefixIcon: Icon(Icons.search, size: 20),
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  final String query;
  final OmniSearchResults? results;
  final bool isLoading;
  final String? error;
  final MusicLibrary musicLibrary;
  final ValueChanged<SongViewData> onSongTap;
  final ValueChanged<AlbumViewData> onAlbumTap;
  final ValueChanged<PlaylistViewData> onPlaylistTap;

  const _ResultsBody({
    required this.query,
    required this.results,
    required this.isLoading,
    required this.error,
    required this.musicLibrary,
    required this.onSongTap,
    required this.onAlbumTap,
    required this.onPlaylistTap,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const _CenteredMessage(text: "search your library");
    }
    if (error != null) {
      return _CenteredMessage(text: error!);
    }
    if (isLoading && results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = results;
    if (data == null || data.isEmpty) {
      return const _CenteredMessage(text: "no results");
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: true,
      children: [
        if (data.playlists.isNotEmpty)
          _ResultSection(
            title: "Playlists",
            children: [
              for (final playlist in data.playlists)
                _PlaylistResultTile(
                  playlist: playlist,
                  onTap: () => onPlaylistTap(playlist),
                ),
            ],
          ),
        if (data.albums.isNotEmpty)
          _ResultSection(
            title: "Albums",
            children: [
              for (final album in data.albums)
                _AlbumResultTile(album: album, onTap: () => onAlbumTap(album)),
            ],
          ),
        if (data.songs.isNotEmpty)
          _ResultSection(
            title: "Songs",
            children: [
              for (final song in data.songs)
                _SongResultTile(
                  song: song,
                  musicLibrary: musicLibrary,
                  onTap: () => onSongTap(song),
                ),
            ],
          ),
      ],
    );
  }
}

class _ResultSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ResultSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              title,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SongResultTile extends StatelessWidget {
  final SongViewData song;
  final MusicLibrary musicLibrary;
  final VoidCallback onTap;

  const _SongResultTile({
    required this.song,
    required this.musicLibrary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: coverImg(song.coverPath, 44, cacheSize: 132),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        musicLibrary.artistsDisplay(song),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const _KindLabel(label: "song"),
      onTap: onTap,
    );
  }
}

class _AlbumResultTile extends StatelessWidget {
  final AlbumViewData album;
  final VoidCallback onTap;

  const _AlbumResultTile({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: coverImg(album.coverPath, 44, cacheSize: 132),
      ),
      title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        album.artists.join(', '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const _KindLabel(label: "album"),
      onTap: onTap,
    );
  }
}

class _PlaylistResultTile extends StatelessWidget {
  final PlaylistViewData playlist;
  final VoidCallback onTap;

  const _PlaylistResultTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: _PlaylistIcon(playlist: playlist),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        "${playlist.songCount} songs",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const _KindLabel(label: "playlist"),
      onTap: onTap,
    );
  }
}

class _PlaylistIcon extends StatelessWidget {
  final PlaylistViewData playlist;

  const _PlaylistIcon({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: playlist.isSystem
          ? const Icon(Icons.favorite, color: Colors.redAccent, size: 22)
          : Text(
              _initials(playlist.name),
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r"\s+")).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return "?";
    final first = parts.first.substring(0, 1);
    if (parts.length == 1) return first.toUpperCase();
    final second = parts.elementAt(1).substring(0, 1);
    return (first + second).toUpperCase();
  }
}

class _KindLabel extends StatelessWidget {
  final String label;

  const _KindLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: TextStyle(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        fontSize: 11,
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String text;

  const _CenteredMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Center(
        child: Text(text, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }
}

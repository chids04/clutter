import 'package:flutter/material.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/library/presentation/widgets/song_context_menu.dart';
import 'package:clutter/shared/presentation/cover_image.dart';

class SongDelegate extends StatefulWidget {
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
  State<SongDelegate> createState() => _SongDelegateState();
}

class _SongDelegateState extends State<SongDelegate>
    with SingleTickerProviderStateMixin {
  static const double _queueThreshold = 72;
  static const double _maxDragExtent = 112;
  static const Duration _settleDuration = Duration(milliseconds: 180);

  double _dragOffset = 0;
  bool _isDragging = false;
  late final AnimationController _tapController;
  late final Animation<double> _tapScale;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _tapScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.985,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.985,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 70,
      ),
    ]).animate(_tapController);
  }

  @override
  void didUpdateWidget(covariant SongDelegate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _dragOffset = 0;
      _isDragging = false;
      _tapController.reset();
    }
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _tapController.forward(from: 0);
    widget.musicLibrary.onPlaySong(widget.song.id);
  }

  void _handleDragStart(DragStartDetails details) {
    _tapController.reset();
    setState(() {
      _isDragging = true;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, _maxDragExtent);
    });
  }

  void _settleDrag({required bool queueSong}) {
    if (queueSong) widget.musicLibrary.queueSongNext(widget.song);
    setState(() {
      _isDragging = false;
      _dragOffset = 0;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    _settleDrag(queueSong: _dragOffset >= _queueThreshold);
  }

  void _handleDragCancel() {
    _settleDrag(queueSong: false);
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final musicLibrary = widget.musicLibrary;
    final isCurrentSong = musicLibrary.currentSong?.id == song.id;
    final colors = Theme.of(context).colorScheme;
    final liked = musicLibrary.isLiked(song.id);
    final settleDuration = _isDragging ? Duration.zero : _settleDuration;

    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: AnimatedContainer(
              duration: settleDuration,
              curve: Curves.easeOutCubic,
              width: _dragOffset,
              color: colors.primary,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 16),
              child: _dragOffset < 44
                  ? null
                  : Icon(Icons.playlist_play, color: colors.onPrimary),
            ),
          ),
          AnimatedContainer(
            duration: settleDuration,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _handleDragStart,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              onHorizontalDragCancel: _handleDragCancel,
              onLongPressStart: (details) => showSongContextMenu(
                context,
                globalPosition: details.globalPosition,
                song: song,
                musicLibrary: musicLibrary,
                onRemoveFromPlaylist: widget.onRemoveFromPlaylist,
              ),
              onSecondaryTapDown: (details) => showSongContextMenu(
                context,
                globalPosition: details.globalPosition,
                song: song,
                musicLibrary: musicLibrary,
                onRemoveFromPlaylist: widget.onRemoveFromPlaylist,
              ),
              child: ScaleTransition(
                scale: _tapScale,
                child: InkWell(
                  onTap: _handleTap,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  child: ListTile(
                    leading: coverImg(song.coverPath, 50, cacheSize: 150),
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
                            style: const ButtonStyle(
                              splashFactory: NoSplash.splashFactory,
                              overlayColor: WidgetStatePropertyAll(
                                Colors.transparent,
                              ),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/library/presentation/widgets/song_context_menu.dart';
import 'package:clutter/shared/presentation/cover_image.dart';

class SongDelegate extends StatefulWidget {
  final SongViewData song;
  final MusicLibrary musicLibrary;
  final VoidCallback? onRemoveFromPlaylist;
  final bool showTrackNumber;

  const SongDelegate({
    super.key,
    required this.song,
    required this.musicLibrary,
    this.onRemoveFromPlaylist,
    this.showTrackNumber = false,
  });

  @override
  State<SongDelegate> createState() => _SongDelegateState();
}

class _SongDelegateState extends State<SongDelegate>
    with TickerProviderStateMixin {
  static const double _queueThreshold = 72;
  static const double _maxDragExtent = 112;
  static const Duration _settleDuration = Duration(milliseconds: 180);
  static const double _statusMarkerWidth = 10;
  static const double _trackNumberWidth = 28;
  static const double _leadingItemGap = 8;
  static const double _coverSize = 50;

  double _dragOffset = 0;
  bool _isDragging = false;
  late final AnimationController _tapController;
  late final Animation<double> _tapScale;
  late final AnimationController _eqController;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 270),
    );
    _tapScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.98,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.98,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 50,
      ),
    ]).animate(_tapController);
    _eqController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _syncEqAnimation();
  }

  @override
  void didUpdateWidget(covariant SongDelegate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _dragOffset = 0;
      _isDragging = false;
      _tapController.reset();
    }
    _syncEqAnimation();
  }

  void _syncEqAnimation() {
    final isCurrent = widget.musicLibrary.currentSong?.id == widget.song.id;
    final playing = isCurrent && widget.musicLibrary.isPlaying;
    if (playing) {
      if (!_eqController.isAnimating) {
        _eqController.repeat(reverse: true);
      }
    } else {
      _eqController.stop();
      _eqController.value = 0.35;
    }
  }

  @override
  void dispose() {
    _tapController.dispose();
    _eqController.dispose();
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

  Widget _statusMarker(Color onSurface, bool isCurrent, bool isPlaying) {
    if (!isCurrent) {
      return const SizedBox(width: _statusMarkerWidth);
    }
    if (!isPlaying) {
      return SizedBox(
        width: _statusMarkerWidth,
        child: Center(
          child: Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: onSurface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: _statusMarkerWidth,
      child: AnimatedBuilder(
        animation: _eqController,
        builder: (context, _) {
          final t = _eqController.value;
          final heights = <double>[6 + 10 * t, 14 - 8 * t, 8 + 8 * (1 - t)];
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < heights.length; i++) ...[
                    if (i > 0) const SizedBox(width: 1.5),
                    Container(
                      width: 2.2,
                      height: heights[i],
                      decoration: BoxDecoration(
                        color: onSurface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final musicLibrary = widget.musicLibrary;
    final isCurrentSong = musicLibrary.currentSong?.id == song.id;
    final isPlaying = isCurrentSong && musicLibrary.isPlaying;
    final colors = Theme.of(context).colorScheme;
    final liked = musicLibrary.isLiked(song.id);
    final settleDuration = _isDragging ? Duration.zero : _settleDuration;
    _syncEqAnimation();

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
                    leading: SizedBox(
                      width:
                          _statusMarkerWidth +
                          _leadingItemGap +
                          _coverSize +
                          (widget.showTrackNumber
                              ? _leadingItemGap + _trackNumberWidth
                              : 0),
                      child: Row(
                        children: [
                          KeyedSubtree(
                            key: ValueKey('song-status-${song.id}'),
                            child: _statusMarker(
                              colors.onSurface,
                              isCurrentSong,
                              isPlaying,
                            ),
                          ),
                          if (widget.showTrackNumber) ...[
                            const SizedBox(width: _leadingItemGap),
                            SizedBox(
                              width: _trackNumberWidth,
                              child: Text(
                                song.trackNum > 0 ? '${song.trackNum}' : '–',
                                key: ValueKey('song-track-number-${song.id}'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: _leadingItemGap),
                          coverImg(song.coverPath, _coverSize, cacheSize: 150),
                        ],
                      ),
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isCurrentSong
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: colors.onSurface.withValues(
                          alpha: isCurrentSong ? 1.0 : 0.92,
                        ),
                      ),
                    ),
                    subtitle: Text(
                      musicLibrary.artistsDisplay(song),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        color: liked
                            ? Colors.redAccent
                            : colors.onSurface.withValues(alpha: 0.85),
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

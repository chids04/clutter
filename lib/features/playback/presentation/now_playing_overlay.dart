import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/shared/presentation/cover_image.dart';
import 'package:clutter/shared/theme/app_colors.dart';

Future<void> showNowPlayingOverlay(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'now playing',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) {
      return const _NowPlayingOverlay();
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class _DismissNowPlayingIntent extends Intent {
  const _DismissNowPlayingIntent();
}

class _NowPlayingOverlay extends StatefulWidget {
  const _NowPlayingOverlay();

  @override
  State<_NowPlayingOverlay> createState() => _NowPlayingOverlayState();
}

class _NowPlayingOverlayState extends State<_NowPlayingOverlay>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _showQueue = false;
  bool _queueClosing = false;
  late final AnimationController _queueController;
  late final CurvedAnimation _queueCurve;
  late final Animation<Offset> _queueSlide;

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _queueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _queueCurve = CurvedAnimation(
      parent: _queueController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _queueSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(_queueCurve);
  }

  @override
  void dispose() {
    _queueCurve.dispose();
    _queueController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return "0:00";
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _dismiss() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _showQueueLayer() {
    if (_showQueue) return;
    setState(() {
      _showQueue = true;
      _queueClosing = false;
    });
    _queueController.forward(from: 0);
  }

  void _hideQueueLayer() {
    if (!_showQueue || _queueClosing) return;
    setState(() {
      _queueClosing = true;
    });
    unawaited(
      _queueController.reverse().then<void>((_) {
        if (!mounted) return;
        setState(() {
          _dragOffset = 0;
          _showQueue = false;
          _queueClosing = false;
        });
      }),
    );
  }

  void _dismissCurrentLayer() {
    if (_showQueue) {
      _hideQueueLayer();
    } else {
      _dismiss();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_queueClosing) return;
    if (details.delta.dy < 0 && _dragOffset <= 0) return;
    setState(() {
      _dragOffset = math.max(0, _dragOffset + details.delta.dy);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_queueClosing) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 120 || velocity > 700) {
      _dismissCurrentLayer();
      return;
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _DismissNowPlayingIntent(),
      },
      child: Actions(
        actions: {
          _DismissNowPlayingIntent: CallbackAction<_DismissNowPlayingIntent>(
            onInvoke: (_) {
              _dismissCurrentLayer();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: AppColors.darkBackground,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(
                0,
                _showQueue ? 0 : _dragOffset,
                0,
              ),
              child: GestureDetector(
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                behavior: HitTestBehavior.translucent,
                child: SafeArea(
                  child: Consumer<MusicLibrary>(
                    builder: (context, musicLibrary, _) {
                      final current = musicLibrary.currentSong;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Column(
                            children: [
                              const _OverlayTitle(title: "now playing"),
                              Expanded(
                                child: _NowPlayingBody(
                                  musicLibrary: musicLibrary,
                                  current: current,
                                  theme: theme,
                                  media: media,
                                  isDesktop: _isDesktop,
                                  formatDuration: _formatDuration,
                                  onShowQueue: _showQueueLayer,
                                ),
                              ),
                            ],
                          ),
                          IgnorePointer(
                            ignoring: !_showQueue || _queueClosing,
                            child: ExcludeSemantics(
                              excluding: !_showQueue,
                              child: SlideTransition(
                                position: _queueSlide,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOut,
                                  transform: Matrix4.translationValues(
                                    0,
                                    _dragOffset,
                                    0,
                                  ),
                                  child: ColoredBox(
                                    key: const ValueKey(
                                      "now-playing-queue-layer",
                                    ),
                                    color: AppColors.darkBackground,
                                    child: Column(
                                      children: [
                                        const _OverlayTitle(title: "queue"),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 56,
                                            ),
                                            child: _ExpandedQueue(
                                              musicLibrary: musicLibrary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 4,
                            bottom: 4,
                            child: IconButton(
                              key: const ValueKey("now-playing-dismiss"),
                              tooltip: _showQueue ? "hide queue" : "close",
                              onPressed: _dismissCurrentLayer,
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 32,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                              style: const ButtonStyle(
                                minimumSize: WidgetStatePropertyAll(
                                  Size(48, 48),
                                ),
                                splashFactory: NoSplash.splashFactory,
                                overlayColor: WidgetStatePropertyAll(
                                  Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayTitle extends StatelessWidget {
  final String title;

  const _OverlayTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 52,
      child: Center(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingBody extends StatelessWidget {
  final MusicLibrary musicLibrary;
  final SongViewData? current;
  final ThemeData theme;
  final MediaQueryData media;
  final bool isDesktop;
  final String Function(Duration?) formatDuration;
  final VoidCallback onShowQueue;

  const _NowPlayingBody({
    required this.musicLibrary,
    required this.current,
    required this.theme,
    required this.media,
    required this.isDesktop,
    required this.formatDuration,
    required this.onShowQueue,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = theme.colorScheme.onSurface;
    final maxCover = math.min(
      media.size.width - 48,
      math.min(media.size.height * 0.42, 420.0),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: coverImg(
                current?.coverPath,
                maxCover,
                cacheSize: (maxCover * media.devicePixelRatio).round(),
              ),
            ),
          ),
          const Spacer(flex: 2),
          SizedBox(
            width: double.infinity,
            child: Text(
              current?.title ?? "nothing playing",
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: current == null
                    ? onSurface.withValues(alpha: 0.45)
                    : onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: Text(
              current == null ? "" : musicLibrary.artistsDisplay(current!),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _ProgressSection(
            musicLibrary: musicLibrary,
            formatDuration: formatDuration,
          ),
          const SizedBox(height: 8),
          _TransportRow(musicLibrary: musicLibrary, onShowQueue: onShowQueue),
          if (isDesktop) ...[
            const SizedBox(height: 8),
            _DesktopExtras(musicLibrary: musicLibrary),
          ],
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  final MusicLibrary musicLibrary;
  final String Function(Duration?) formatDuration;

  const _ProgressSection({
    required this.musicLibrary,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final max = musicLibrary.playerDuration?.inMilliseconds.toDouble() ?? 0;
    final pos = musicLibrary.playerPosition?.inMilliseconds.toDouble() ?? 0;
    final value = max <= 0 ? 0.0 : pos.clamp(0.0, max);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: onSurface.withValues(alpha: 0.92),
            inactiveTrackColor: onSurface.withValues(alpha: 0.18),
            thumbColor: onSurface,
          ),
          child: Slider(
            value: value,
            max: max <= 0 ? 1.0 : max,
            onChanged: max <= 0
                ? null
                : (v) => musicLibrary.setPlayerPosition(v),
            onChangeStart: max <= 0 ? null : (_) => musicLibrary.startScrub(),
            onChangeEnd: max <= 0 ? null : (_) => musicLibrary.endScrub(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                formatDuration(musicLibrary.playerPosition),
                style: TextStyle(
                  fontSize: 12,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(),
              Text(
                formatDuration(musicLibrary.playerDuration),
                style: TextStyle(
                  fontSize: 12,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransportRow extends StatelessWidget {
  final MusicLibrary musicLibrary;
  final VoidCallback onShowQueue;

  const _TransportRow({required this.musicLibrary, required this.onShowQueue});

  @override
  Widget build(BuildContext context) {
    final hasSong = musicLibrary.currentSong != null;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final liked = musicLibrary.currentSong != null
        ? musicLibrary.isLiked(musicLibrary.currentSong!.id)
        : false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey("now-playing-repeat"),
              tooltip: musicLibrary.loopOne ? "disable loop" : "loop track",
              onPressed: hasSong ? musicLibrary.toggleLoopOne : null,
              icon: Icon(
                musicLibrary.loopOne
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: musicLibrary.loopOne
                    ? onSurface
                    : onSurface.withValues(alpha: 0.55),
              ),
              style: _iconStyle,
            ),
            IconButton(
              key: const ValueKey("now-playing-show-queue"),
              tooltip: "show queue",
              onPressed: onShowQueue,
              icon: Icon(
                Icons.queue_music_rounded,
                color: onSurface.withValues(alpha: 0.7),
              ),
              style: _iconStyle,
            ),
          ],
        ),
        IconButton(
          tooltip: "previous",
          onPressed: musicLibrary.canPlayPrevious
              ? musicLibrary.playPrevious
              : null,
          icon: Icon(
            Icons.skip_previous_rounded,
            size: 40,
            color: onSurface.withValues(
              alpha: musicLibrary.canPlayPrevious ? 0.95 : 0.3,
            ),
          ),
          style: _iconStyle,
        ),
        DecoratedBox(
          decoration: BoxDecoration(color: onSurface, shape: BoxShape.circle),
          child: IconButton(
            tooltip: musicLibrary.isPlaying ? "pause" : "play",
            onPressed: hasSong ? musicLibrary.togglePlay : null,
            icon: Icon(
              musicLibrary.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 36,
              color: AppColors.darkBackground,
            ),
            style: _iconStyle,
          ),
        ),
        IconButton(
          tooltip: "next",
          onPressed: hasSong ? musicLibrary.playNext : null,
          icon: Icon(
            Icons.skip_next_rounded,
            size: 40,
            color: onSurface.withValues(alpha: hasSong ? 0.95 : 0.3),
          ),
          style: _iconStyle,
        ),
        IconButton(
          tooltip: liked ? "unlike" : "like",
          onPressed: musicLibrary.currentSong == null
              ? null
              : () => musicLibrary.toggleLiked(musicLibrary.currentSong!),
          icon: Icon(
            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: liked ? Colors.redAccent : onSurface.withValues(alpha: 0.7),
          ),
          style: _iconStyle,
        ),
      ],
    );
  }

  static const _iconStyle = ButtonStyle(
    splashFactory: NoSplash.splashFactory,
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
  );
}

class _DesktopExtras extends StatelessWidget {
  final MusicLibrary musicLibrary;

  const _DesktopExtras({required this.musicLibrary});

  IconData _volumeIconFor(double v) {
    if (v <= 0.0) return Icons.volume_off_rounded;
    if (v < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(
          _volumeIconFor(musicLibrary.volume),
          size: 20,
          color: onSurface.withValues(alpha: 0.7),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: musicLibrary.volume,
              onChanged: musicLibrary.setVolume,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandedQueue extends StatelessWidget {
  final MusicLibrary musicLibrary;

  const _ExpandedQueue({required this.musicLibrary});

  @override
  Widget build(BuildContext context) {
    final q = musicLibrary.queue;
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("${q.length} queued", style: theme.textTheme.labelLarge),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BouncyShuffleButton(
                      onPressed: q.length < 2
                          ? null
                          : musicLibrary.shuffleQueue,
                    ),
                    TextButton(
                      onPressed: q.isEmpty
                          ? null
                          : musicLibrary.toggleLoopQueue,
                      child: Text(
                        musicLibrary.loopQueue ? "loop on" : "loop off",
                        style: TextStyle(
                          color: musicLibrary.loopQueue
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: q.isEmpty ? null : musicLibrary.clearQueue,
                      child: const Text("clear"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? Center(
                  child: Text(
                    "queue is empty",
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: q.length,
                  onReorder: (from, to) {
                    if (to > from) to -= 1;
                    musicLibrary.moveQueueItem(from, to);
                  },
                  itemBuilder: (context, i) {
                    final song = q[i];
                    return ListTile(
                      key: ValueKey("np-queue-${song.id}-$i"),
                      leading: coverImg(song.coverPath, 44, cacheSize: 132),
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
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => musicLibrary.removeFromQueue(i),
                        style: const ButtonStyle(
                          splashFactory: NoSplash.splashFactory,
                          overlayColor: WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BouncyShuffleButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const _BouncyShuffleButton({required this.onPressed});

  @override
  State<_BouncyShuffleButton> createState() => _BouncyShuffleButtonState();
}

class _BouncyShuffleButtonState extends State<_BouncyShuffleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.82,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.82,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 25,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _bounceAndShuffle() {
    _controller.forward(from: 0);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey("shuffle-queue"),
      tooltip: "shuffle queue",
      onPressed: widget.onPressed == null ? null : _bounceAndShuffle,
      icon: ScaleTransition(
        key: const ValueKey("shuffle-queue-scale"),
        scale: _scale,
        child: const Icon(Icons.shuffle_rounded),
      ),
      style: const ButtonStyle(
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}

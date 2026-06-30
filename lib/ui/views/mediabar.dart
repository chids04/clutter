import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/widgets/song_context_menu.dart';
import 'package:clutter/services/cover_img_loader.dart';

const double _kControlSize = 40.0;

class MediaBar extends StatefulWidget {
  final ValueListenable<LibraryPage> activeLibraryPageListenable;
  final ValueChanged<LibraryPage> onLibraryPageSelected;

  const MediaBar({
    super.key,
    required this.activeLibraryPageListenable,
    required this.onLibraryPageSelected,
  });

  @override
  State<MediaBar> createState() => _MediaBarState();
}

class _MediaBarState extends State<MediaBar> {
  bool _showQueue = false;

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  String _formatDuration(Duration? duration) {
    if (duration == null) return "";
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Widget _queueToggle() {
    return IconButton(
      icon: Icon(_showQueue ? Icons.queue_music : Icons.queue_music_outlined),
      tooltip: _showQueue ? "Hide queue" : "Show queue",
      onPressed: () => setState(() => _showQueue = !_showQueue),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: _kControlSize,
        minHeight: _kControlSize,
      ),
    );
  }

  Widget _playbackControls(MusicLibrary musicLibrary) {
    final hasSong = musicLibrary.currentSong != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 21),
          onPressed: musicLibrary.canPlayPrevious
              ? () => musicLibrary.playPrevious()
              : null,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 29),
        ),
        IconButton(
          icon: Icon(
            musicLibrary.isPlaying ? Icons.pause : Icons.play_arrow,
            size: 24,
          ),
          onPressed: hasSong ? () => musicLibrary.togglePlay() : null,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 35, minHeight: 29),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, size: 21),
          onPressed: hasSong ? () => musicLibrary.playNext() : null,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 29),
        ),
      ],
    );
  }

  Widget _slimSlider(MusicLibrary musicLibrary) {
    // Cold-start resume sets playerPosition before the audioplayer has loaded
    // the source, so playerDuration can be null/0 while position > 0. Clamp to
    // keep Slider's value >= min && value <= max invariant.
    final max = musicLibrary.playerDuration?.inMilliseconds.toDouble() ?? 0;
    final pos = musicLibrary.playerPosition?.inMilliseconds.toDouble() ?? 0;
    final value = max <= 0 ? 0.0 : pos.clamp(0.0, max);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
      child: Slider(
        value: value,
        max: max <= 0 ? 1.0 : max,
        onChanged: max <= 0 ? null : (v) => musicLibrary.setPlayerPosition(v),
        onChangeStart: max <= 0 ? null : (_) => musicLibrary.startScrub(),
        onChangeEnd: max <= 0 ? null : (_) => musicLibrary.endScrub(),
      ),
    );
  }

  Widget _sliderRow(MusicLibrary musicLibrary, double fontSize) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            _formatDuration(musicLibrary.playerPosition),
            style: TextStyle(fontSize: fontSize),
          ),
        ),
        Expanded(child: _slimSlider(musicLibrary)),
        SizedBox(
          width: 34,
          child: Text(
            _formatDuration(musicLibrary.playerDuration),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: fontSize),
          ),
        ),
      ],
    );
  }

  double _coverSizeFor(double width) {
    if (width < 360) return 32;
    if (width < 600) return 36;
    if (width < 900) return 40;
    return 44;
  }

  Widget _buildBar(MusicLibrary musicLibrary, SongViewData? current) {
    final theme = Theme.of(context);
    return GestureDetector(
      onLongPressStart: current == null
          ? null
          : (d) => showSongContextMenu(
              context,
              globalPosition: d.globalPosition,
              song: current,
              musicLibrary: musicLibrary,
            ),
      onSecondaryTapDown: current == null
          ? null
          : (d) => showSongContextMenu(
              context,
              globalPosition: d.globalPosition,
              song: current,
              musicLibrary: musicLibrary,
            ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final coverSize = _coverSizeFor(constraints.maxWidth);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                coverImg(current?.coverPath, coverSize),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              current?.title ?? "nothing playing",
                              textAlign: TextAlign.left,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: current == null
                                    ? Colors.grey
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          _playbackControls(musicLibrary),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                      if (current != null)
                        Text(
                          musicLibrary.artistsDisplay(current),
                          textAlign: TextAlign.left,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      _sliderRow(musicLibrary, 11),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_isDesktop) _VolumeControl(musicLibrary: musicLibrary),
                    _LoopButton(musicLibrary: musicLibrary),
                    _queueToggle(),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicLibrary>(
      builder: (context, musicLibrary, _) {
        final current = musicLibrary.currentSong;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBar(musicLibrary, current),
            if (!_isDesktop)
              _LibraryQuickNav(
                activePageListenable: widget.activeLibraryPageListenable,
                onPageSelected: widget.onLibraryPageSelected,
              ),
            if (_showQueue)
              _QueuePanel(
                musicLibrary: musicLibrary,
                buildCover: (path) => coverImg(path, 36, cacheSize: 108),
                showEmptyMessage: _isDesktop,
              ),
          ],
        );
      },
    );
  }
}

class _LibraryQuickNav extends StatelessWidget {
  final ValueListenable<LibraryPage> activePageListenable;
  final ValueChanged<LibraryPage> onPageSelected;

  const _LibraryQuickNav({
    required this.activePageListenable,
    required this.onPageSelected,
  });

  IconData _iconFor(LibraryPage page) {
    return switch (page) {
      LibraryPage.songs => Icons.music_note,
      LibraryPage.albums => Icons.album,
      LibraryPage.artists => Icons.person,
      LibraryPage.playlists => Icons.queue_music,
      LibraryPage.recentlyPlayed => Icons.history,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.colorScheme.onSurface.withValues(alpha: 0.58);
    return ValueListenableBuilder<LibraryPage>(
      valueListenable: activePageListenable,
      builder: (context, activePage, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.dividerTheme.color ?? Colors.transparent,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: LibraryPage.values.map((page) {
              final active = page == activePage;
              return IconButton(
                icon: Icon(_iconFor(page), size: 22),
                tooltip: page.label,
                color: active ? theme.colorScheme.primary : inactive,
                onPressed: () => onPageSelected(page),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: _kControlSize,
                  minHeight: 34,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _VolumeControl extends StatefulWidget {
  final MusicLibrary musicLibrary;

  const _VolumeControl({required this.musicLibrary});

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _hovered = false;

  IconData _volumeIconFor(double v) {
    if (v <= 0.0) return Icons.volume_off;
    if (v < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    final musicLibrary = widget.musicLibrary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: _hovered ? 110 : 0,
            height: _kControlSize,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerRight,
                minWidth: 110,
                maxWidth: 110,
                minHeight: _kControlSize,
                maxHeight: _kControlSize,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: musicLibrary.volume,
                    onChanged: (v) => musicLibrary.setVolume(v),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(_volumeIconFor(musicLibrary.volume)),
            tooltip: "Volume",
            onPressed: () {},
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(
              minWidth: _kControlSize,
              minHeight: _kControlSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoopButton extends StatelessWidget {
  final MusicLibrary musicLibrary;

  const _LoopButton({required this.musicLibrary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = musicLibrary.loopOne;
    return IconButton(
      icon: Icon(active ? Icons.repeat_one : Icons.repeat, size: 21),
      tooltip: active ? "Disable loop" : "Loop current track",
      color: active ? theme.colorScheme.primary : null,
      onPressed: musicLibrary.currentSong == null
          ? null
          : () => musicLibrary.toggleLoopOne(),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: _kControlSize,
        minHeight: _kControlSize,
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  final MusicLibrary musicLibrary;
  final Widget Function(String?) buildCover;
  final bool showEmptyMessage;

  const _QueuePanel({
    required this.musicLibrary,
    required this.buildCover,
    required this.showEmptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final q = musicLibrary.queue;
    final theme = Theme.of(context);
    final loopQueue = musicLibrary.loopQueue;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 2),
      child: Row(
        children: [
          Text("queue", style: theme.textTheme.labelLarge),
          const Spacer(),
          TextButton.icon(
            icon: Icon(
              Icons.repeat,
              size: 18,
              color: loopQueue ? theme.colorScheme.primary : null,
            ),
            label: const Text("Loop queue"),
            style: TextButton.styleFrom(
              foregroundColor: loopQueue
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.72),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: musicLibrary.toggleLoopQueue,
          ),
        ],
      ),
    );

    if (q.isEmpty) {
      if (!showEmptyMessage) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                "queue is empty",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ],
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: true,
              itemCount: q.length,
              onReorder: (from, to) {
                if (to > from) to -= 1;
                musicLibrary.moveQueueItem(from, to);
              },
              itemBuilder: (context, i) {
                final song = q[i];
                return ListTile(
                  key: ValueKey("queue-${song.id}-$i"),
                  leading: buildCover(song.coverPath),
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

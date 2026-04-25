import 'dart:io';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/widgets/song_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MediaBar extends StatefulWidget {
  const MediaBar({super.key});

  @override
  State<MediaBar> createState() => _MediaBarState();
}

class _MediaBarState extends State<MediaBar> {
  bool _expanded = false;
  bool _showQueue = false;

  Widget _coverImg(String? coverPath, double size, {int? cacheSide}) {
    if (coverPath == null) {
      return SvgPicture.asset(
        "assets/note.svg",
        width: size,
        height: size,
        colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
      );
    }
    final cache = cacheSide ?? (size * 3).toInt();
    return Image.file(
      File(coverPath),
      width: size,
      height: size,
      cacheWidth: cache,
      cacheHeight: cache,
    );
  }

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
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  Widget _playbackControls(MusicLibrary musicLibrary, {required bool compact}) {
    final skipSize = compact ? 22.0 : 26.0;
    final playSize = compact ? 24.0 : 30.0;
    final minH = compact ? 32.0 : 36.0;
    final minW = compact ? 32.0 : 40.0;
    final playMinW = compact ? 36.0 : 44.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.skip_previous, size: skipSize),
          onPressed: () => musicLibrary.playPrevious(),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(minWidth: minW, minHeight: minH),
        ),
        IconButton(
          icon: Icon(
            musicLibrary.isPlaying ? Icons.pause : Icons.play_arrow,
            size: playSize,
          ),
          onPressed: () => musicLibrary.togglePlay(),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(minWidth: playMinW, minHeight: minH),
        ),
        IconButton(
          icon: Icon(Icons.skip_next, size: skipSize),
          onPressed: () => musicLibrary.playNext(),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(minWidth: minW, minHeight: minH),
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
        onChangeStart: max <= 0 ? null : (_) => musicLibrary.pause(),
        onChangeEnd: max <= 0 ? null : (_) => musicLibrary.resume(),
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

  Widget _collapsedInfoColumn(MusicLibrary musicLibrary, SongViewData? current) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          current?.title ?? "nothing playing",
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: current == null
                ? Colors.grey
                : theme.colorScheme.onSurface,
          ),
        ),
        if (current != null)
          Text(
            musicLibrary.artistsDisplay(current),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        _sliderRow(musicLibrary, 10),
      ],
    );
  }

  Widget _buildCollapsed(MusicLibrary musicLibrary, SongViewData? current) {
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
      child: InkWell(
        onTap: current == null ? null : () => setState(() => _expanded = true),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
          child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            if (isWide) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Balance the queue toggle (40px) on the right so the
                      // info column is truly centered within the bar.
                      const SizedBox(width: 40),
                      Expanded(
                        child: _collapsedInfoColumn(musicLibrary, current),
                      ),
                      _queueToggle(),
                    ],
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: _playbackControls(musicLibrary, compact: false),
                  ),
                ],
              );
            }
            // Compact controls row: skip(32) + play(36) + skip(32) = 100px.
            // Balance that on the left so the info column stays centered.
            return Row(
              children: [
                const SizedBox(width: 100),
                Expanded(child: _collapsedInfoColumn(musicLibrary, current)),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _playbackControls(musicLibrary, compact: true),
                    _queueToggle(),
                  ],
                ),
              ],
            );
          },
        ),
        ),
      ),
    );
  }

  Widget _buildExpanded(MusicLibrary musicLibrary, SongViewData? current) {
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
      child: InkWell(
        onTap: () => setState(() => _expanded = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _coverImg(current?.coverPath, 56),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current?.title ?? "nothing playing",
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (current != null)
                    Text(
                      musicLibrary.artistsDisplay(current),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _sliderRow(musicLibrary, 11),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: _playbackControls(musicLibrary, compact: false),
                  ),
                ],
              ),
            ),
            // Match cover (56) + spacer (10) = 66px on the left so the
            // info column is truly centered.
            SizedBox(
              width: 66,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _queueToggle(),
              ),
            ),
          ],
        ),
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
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: _expanded
                  ? _buildExpanded(musicLibrary, current)
                  : _buildCollapsed(musicLibrary, current),
            ),
            if (_showQueue)
              _QueuePanel(
                musicLibrary: musicLibrary,
                buildCover: (path) => _coverImg(path, 36, cacheSide: 108),
              ),
          ],
        );
      },
    );
  }
}

class _QueuePanel extends StatelessWidget {
  final MusicLibrary musicLibrary;
  final Widget Function(String?) buildCover;

  const _QueuePanel({required this.musicLibrary, required this.buildCover});

  @override
  Widget build(BuildContext context) {
    final q = musicLibrary.queue;
    if (q.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            "queue is empty",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
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
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/shared/presentation/search_sliver_app_bar.dart';
import 'package:clutter/features/library/presentation/widgets/song_delegate.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';

class SongView extends StatefulWidget {
  const SongView({super.key});

  @override
  State<SongView> createState() => _SongViewState();
}

class _SongViewState extends State<SongView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SongViewData>? _results; // null => use cached library.songs
  ScrollController? _scrollController;

  void _resetScrollPosition() {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final q = raw.trim();
      if (q.isEmpty) {
        if (mounted) {
          _resetScrollPosition();
          setState(() => _results = null);
        }
        return;
      }
      final lib = context.read<MusicLibrary>();
      final res = await lib.searchSongs(q);
      if (mounted) {
        _resetScrollPosition();
        setState(() => _results = res);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicLibrary>(
      builder: (context, musicLibrary, _) {
        if (musicLibrary.songs.isEmpty && musicLibrary.isScanning) {
          return const Center(child: CircularProgressIndicator());
        }
        final songs = _results ?? musicLibrary.songs;
        return RememberedScrollPosition(
          id: 'library:songs',
          onControllerChanged: (controller) => _scrollController = controller,
          builder: (context, scrollController) => CustomScrollView(
            controller: scrollController,
            slivers: [
              SearchSliverAppBar(
                controller: _controller,
                hint: "search songs",
                onChanged: _onQueryChanged,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      key: const ValueKey('shuffle-library'),
                      onPressed: musicLibrary.songs.isEmpty
                          ? null
                          : musicLibrary.queueLibraryShuffled,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('shuffle all'),
                    ),
                  ),
                ),
              ),
              if (songs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      "no results",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverList.separated(
                    itemCount: songs.length,
                    itemBuilder: (context, index) => SongDelegate(
                      song: songs[index],
                      musicLibrary: musicLibrary,
                    ),
                    separatorBuilder: (context, index) => const Divider(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

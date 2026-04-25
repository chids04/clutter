import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/widgets/search_sliver_app_bar.dart';
import 'package:clutter/ui/widgets/song_delegate.dart';

class SongView extends StatefulWidget {
  const SongView({super.key});

  @override
  State<SongView> createState() => _SongViewState();
}

class _SongViewState extends State<SongView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SongViewData>? _results; // null => use cached library.songs

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final q = raw.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _results = null);
        return;
      }
      final lib = context.read<MusicLibrary>();
      final res = await lib.searchSongs(q);
      if (mounted) setState(() => _results = res);
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
        return CustomScrollView(
          slivers: [
            SearchSliverAppBar(
              controller: _controller,
              hint: "search songs",
              onChanged: _onQueryChanged,
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
        );
      },
    );
  }
}

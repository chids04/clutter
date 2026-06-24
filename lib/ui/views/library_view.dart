import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/ui/views/albums_view.dart';
import 'package:clutter/ui/views/artists_view.dart';
import 'package:clutter/ui/views/playlists_view.dart';
import 'package:clutter/ui/views/songs_view.dart';
import 'package:clutter/ui/widgets/song_delegate.dart';

class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  LibraryPage currentPage = LibraryPage.songs;

  void updateState(LibraryPage newPage) {
    setState(() {
      currentPage = newPage;
    });
  }

  Future<void> _promptCreatePlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("new playlist"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "playlist name"),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text("create"),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      await context.read<MusicLibrary>().createPlaylist(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(currentPage.label),
            const Spacer(),
            Row(
              spacing: 5,
              children: [
                const Text("list as", style: TextStyle(fontSize: 12)),
                DisplayOptDropdown(
                  onPageChanged: updateState,
                  currentPage: currentPage,
                ),
              ],
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0.0,
        shape: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.transparent,
            width: 1.0,
          ),
        ),
      ),
      floatingActionButton: currentPage == LibraryPage.playlists
          ? FloatingActionButton(
              tooltip: "new playlist",
              onPressed: _promptCreatePlaylist,
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: switch (currentPage) {
          LibraryPage.songs => const SongView(),
          LibraryPage.albums => const AlbumsView(),
          LibraryPage.artists => const ArtistsView(),
          LibraryPage.playlists => const PlaylistsView(),
          LibraryPage.recentlyPlayed => const RecentlyPlayedView(),
        },
      ),
    );
  }
}

class DisplayOptDropdown extends StatefulWidget {
  const DisplayOptDropdown({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
  });

  final LibraryPage currentPage;
  final Function(LibraryPage) onPageChanged;

  @override
  State<DisplayOptDropdown> createState() => _DisplayOptDropdownState();
}

class _DisplayOptDropdownState extends State<DisplayOptDropdown> {
  @override
  Widget build(BuildContext context) {
    return DropdownButton<LibraryPage>(
      value: widget.currentPage,
      icon: const Icon(Icons.arrow_downward),
      elevation: 16,
      style: const TextStyle(fontSize: 12),
      onChanged: (LibraryPage? value) {
        setState(() {
          if (value != null) {
            widget.onPageChanged(value);
          }
        });
      },
      items: LibraryPage.values.map<DropdownMenuItem<LibraryPage>>((
        LibraryPage page,
      ) {
        return DropdownMenuItem<LibraryPage>(
          value: page,
          child: Text(page.label),
        );
      }).toList(),
    );
  }
}

class RecentlyPlayedView extends StatelessWidget {
  const RecentlyPlayedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicLibrary>(
      builder: (context, musicLibrary, _) {
        return FutureBuilder<List<SongViewData>>(
          // Rebuild whenever the library changes so plays/deletes refresh
          // the list without the user leaving the tab.
          key: ValueKey(
            "recents-${musicLibrary.totalSongs}-${musicLibrary.currentSong?.id ?? ''}",
          ),
          future: musicLibrary.fetchRecentlyPlayed(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final songs = snapshot.data!;
            if (songs.isEmpty) {
              return const Center(
                child: Text(
                  "nothing played yet",
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: songs.length,
              itemBuilder: (context, i) =>
                  SongDelegate(song: songs[i], musicLibrary: musicLibrary),
              separatorBuilder: (_, _) => const Divider(),
            );
          },
        );
      },
    );
  }
}

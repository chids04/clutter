import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/utils/log.dart';

enum LibraryPage {
  songs("songs"),
  albums("albums"),
  recentlyPlayed("recently played");

  final String label;

  const LibraryPage(this.label);
}

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(currentPage.label),
            Spacer(),
            Row(
              spacing: 5,
              children: [
                Text("list as", style: TextStyle(fontSize: 12)),
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

      body: SafeArea(
        child: switch (currentPage) {
          LibraryPage.songs => SongView(),
          _ => Text("unimplemented rn"),
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

class SongView extends StatelessWidget {
  const SongView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicLibrary>(
      builder: (context, musicLibrary, child) {
        if (musicLibrary.songs.isEmpty && musicLibrary.isScanning) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: musicLibrary.cLibrary.numSongs().toInt(),
          itemBuilder: (context, index) =>
              SongDelegate(index: index, musicLibrary: musicLibrary),
          separatorBuilder: (context, index) => const Divider(),
        );
      },
    );
  }
}

class SongDelegate extends StatefulWidget {
  final int index;
  final MusicLibrary musicLibrary;

  const SongDelegate({
    super.key,
    required this.index,
    required this.musicLibrary,
  });

  @override
  State<SongDelegate> createState() => _SongDelegateState();
}

class _SongDelegateState extends State<SongDelegate> {
  late Future<CSongDart?> _songFuture;

  @override
  void initState() {
    super.initState();
    _songFuture = widget.musicLibrary.cLibrary.getSongByIndex(
      index: BigInt.from(widget.index),
    );
  }

  @override
  void didUpdateWidget(covariant SongDelegate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _songFuture = widget.musicLibrary.cLibrary.getSongByIndex(
        index: BigInt.from(widget.index),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CSongDart?>(
      future: _songFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(title: LinearProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final song = snapshot.data!;
        final musicLibrary = context.watch<MusicLibrary>();

        final isCurrentSong = musicLibrary.currentSong?.id == song.id;

        final leadingStr = musicLibrary.cLibrary.getArtist(
          id: song.artists.leading,
        );
        final featuresStr = song.artists.features
            .map((artistId) => musicLibrary.cLibrary.getArtist(id: artistId))
            .join(', ');

        final artistsStr =
            "$leadingStr ${featuresStr.isNotEmpty ? "feat." : ""} $featuresStr";

        return InkWell(
          onTap: () => musicLibrary.onPlaySong(song.id),
          child: ListTile(
            leading: _buildCoverImg(song),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              artistsStr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: isCurrentSong
                ? const Icon(Icons.play_arrow, color: Colors.green)
                : const Icon(Icons.favorite_border),
          ),
        );
      },
    );
  }

  Widget _buildCoverImg(CSongDart song) {
    final img = song.cover;
    if (img == null) {
      return const SizedBox(
        width: 50,
        height: 50,
        child: Placeholder(color: Colors.red),
      );
    }
    return Image.memory(
      img.data,
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      // Helps performance by not decoding huge images for tiny thumbnails
      cacheWidth: 150,
      cacheHeight: 150,
    );
  }
}

class AlbumsView extends StatelessWidget {
  const AlbumsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicLibrary>(
      builder: (context, musicLibrary, child) {
        if (musicLibrary.songs.isEmpty && musicLibrary.isScanning) {
          return const Center(child: CircularProgressIndicator());
        }

        return const Center(child: CircularProgressIndicator());

        // return ListView.separated(
        //   padding: const EdgeInsets.all(8),
        //   itemCount: musicLibrary.songs.length,
        //   itemBuilder: (context, index) =>
        //       SongDelegate(song: musicLibrary.songs[index]),
        //   separatorBuilder: (context, index) => const Divider(),
        // );
      },
    );
  }
}

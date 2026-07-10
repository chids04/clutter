import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/services/cover_img_loader.dart';
import 'package:clutter/src/rust/api/scanner.dart';

Future<SongViewData?> showSongEditor(
  BuildContext context,
  SongViewData song,
  MusicLibrary library,
) {
  return showDialog<SongViewData>(
    context: context,
    builder: (_) => _SongEditor(song: song, library: library),
  );
}

Future<AlbumViewData?> showAlbumEditor(
  BuildContext context,
  AlbumViewData album,
  MusicLibrary library,
) {
  return showDialog<AlbumViewData>(
    context: context,
    builder: (_) => _AlbumEditor(album: album, library: library),
  );
}

Future<ArtistViewData?> showArtistImageEditor(
  BuildContext context,
  ArtistViewData artist,
  MusicLibrary library,
) {
  return showDialog<ArtistViewData>(
    context: context,
    builder: (_) => _ArtistImageEditor(artist: artist, library: library),
  );
}

Future<PlaylistViewData?> showPlaylistEditor(
  BuildContext context,
  PlaylistViewData playlist,
  MusicLibrary library,
) {
  return showDialog<PlaylistViewData>(
    context: context,
    builder: (_) => _PlaylistEditor(playlist: playlist, library: library),
  );
}

Future<String?> _pickImage() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    dialogTitle: 'choose artwork',
  );
  return result?.files.single.path;
}

List<String> _names(String raw) => raw
    .split(',')
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toList();

class _SongEditor extends StatefulWidget {
  const _SongEditor({required this.song, required this.library});
  final SongViewData song;
  final MusicLibrary library;

  @override
  State<_SongEditor> createState() => _SongEditorState();
}

class _SongEditorState extends State<_SongEditor> {
  late final TextEditingController _title;
  late final TextEditingController _primary;
  late final TextEditingController _features;
  late final TextEditingController _album;
  late final TextEditingController _albumArtists;
  late final TextEditingController _track;
  late final TextEditingController _disc;
  Timer? _debounce;
  List<AlbumViewData> _suggestions = const [];
  String? _selectedAlbumId;
  String? _pickedCover;
  bool _removeCover = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final song = widget.song;
    _title = TextEditingController(text: song.title);
    _primary = TextEditingController(text: song.primaryArtist);
    _features = TextEditingController(text: song.featuredArtists.join(', '));
    _album = TextEditingController(text: song.album);
    _albumArtists = TextEditingController(text: song.albumArtists.join(', '));
    _track = TextEditingController(text: '${song.trackNum}');
    _disc = TextEditingController(text: '${song.discNum}');
    _selectedAlbumId = song.albumId;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in [
      _title,
      _primary,
      _features,
      _album,
      _albumArtists,
      _track,
      _disc,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _searchAlbums(String value) {
    _selectedAlbumId = null;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final results = await widget.library.searchAlbums(value, limit: 8);
      if (mounted) setState(() => _suggestions = results);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final albumChoice = _selectedAlbumId != null
          ? AlbumChoice.existing(albumId: _selectedAlbumId!)
          : AlbumChoice.new_(
              title: _album.text,
              artists: _names(_albumArtists.text),
            );
      final cover = _pickedCover != null
          ? CoverArtEdit.replace(sourcePath: _pickedCover!)
          : _removeCover
          ? const CoverArtEdit.remove()
          : const CoverArtEdit.keep();
      final updated = await widget.library.updateSong(
        SongEditRequest(
          songId: widget.song.id,
          title: _title.text,
          primaryArtist: _primary.text,
          featuredArtists: _names(_features.text),
          trackNum: int.tryParse(_track.text) ?? 0,
          discNum: int.tryParse(_disc.text) ?? 0,
          album: albumChoice,
          cover: cover,
        ),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('could not update song: $error')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('edit song'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ArtworkChooser(
                path: _pickedCover ?? widget.song.coverPath,
                removeLabel: 'use album artwork',
                onChoose: () async {
                  final path = await _pickImage();
                  if (path != null) {
                    setState(() {
                      _pickedCover = path;
                      _removeCover = false;
                    });
                  }
                },
                onRemove: () => setState(() {
                  _pickedCover = null;
                  _removeCover = true;
                }),
              ),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'title'),
              ),
              TextField(
                controller: _primary,
                decoration: const InputDecoration(labelText: 'primary artist'),
              ),
              TextField(
                controller: _features,
                decoration: const InputDecoration(
                  labelText: 'featured artists',
                  helperText: 'separate artists with commas',
                ),
              ),
              TextField(
                controller: _album,
                decoration: const InputDecoration(labelText: 'album'),
                onChanged: _searchAlbums,
              ),
              if (_suggestions.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (_, index) {
                      final album = _suggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(album.title),
                        subtitle: Text(album.artists.join(', ')),
                        onTap: () => setState(() {
                          _selectedAlbumId = album.id;
                          _album.text = album.title;
                          _albumArtists.text = album.artists.join(', ');
                          _suggestions = const [];
                        }),
                      );
                    },
                  ),
                ),
              TextField(
                controller: _albumArtists,
                decoration: const InputDecoration(
                  labelText: 'album artists',
                  helperText: 'separate artists with commas',
                ),
                onChanged: (_) => _selectedAlbumId = null,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _track,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'track'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _disc,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'disc'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('save'),
        ),
      ],
    );
  }
}

class _AlbumEditor extends StatefulWidget {
  const _AlbumEditor({required this.album, required this.library});
  final AlbumViewData album;
  final MusicLibrary library;

  @override
  State<_AlbumEditor> createState() => _AlbumEditorState();
}

class _AlbumEditorState extends State<_AlbumEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.album.title,
  );
  late final TextEditingController _artists = TextEditingController(
    text: widget.album.artists.join(', '),
  );
  String? _pickedCover;
  bool _removeCover = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _artists.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final cover = _pickedCover != null
          ? CoverArtEdit.replace(sourcePath: _pickedCover!)
          : _removeCover
          ? const CoverArtEdit.remove()
          : const CoverArtEdit.keep();
      final result = await widget.library.updateAlbum(
        AlbumEditRequest(
          albumId: widget.album.id,
          title: _title.text,
          artists: _names(_artists.text),
          cover: cover,
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('could not update album: $error')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('edit album'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ArtworkChooser(
            path: _pickedCover ?? widget.album.coverPath,
            onChoose: () async {
              final path = await _pickImage();
              if (path != null) {
                setState(() {
                  _pickedCover = path;
                  _removeCover = false;
                });
              }
            },
            onRemove: () => setState(() {
              _pickedCover = null;
              _removeCover = true;
            }),
          ),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'album title'),
          ),
          TextField(
            controller: _artists,
            decoration: const InputDecoration(
              labelText: 'album artists',
              helperText: 'separate artists with commas',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('save'),
      ),
    ],
  );
}

class _ArtistImageEditor extends StatefulWidget {
  const _ArtistImageEditor({required this.artist, required this.library});
  final ArtistViewData artist;
  final MusicLibrary library;
  @override
  State<_ArtistImageEditor> createState() => _ArtistImageEditorState();
}

class _ArtistImageEditorState extends State<_ArtistImageEditor> {
  String? _picked;
  bool _remove = false;
  bool _saving = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('edit ${widget.artist.name} image'),
    content: _ArtworkChooser(
      path: _picked ?? widget.artist.coverPath,
      removeLabel: 'use album artwork',
      onChoose: () async {
        final path = await _pickImage();
        if (path != null) {
          setState(() {
            _picked = path;
            _remove = false;
          });
        }
      },
      onRemove: () => setState(() {
        _picked = null;
        _remove = true;
      }),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('cancel'),
      ),
      FilledButton(
        onPressed: _saving
            ? null
            : () async {
                setState(() => _saving = true);
                try {
                  final edit = _picked != null
                      ? CoverArtEdit.replace(sourcePath: _picked!)
                      : _remove
                      ? const CoverArtEdit.remove()
                      : const CoverArtEdit.keep();
                  final result = await widget.library.updateArtistImage(
                    widget.artist.id,
                    edit,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context, result);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('could not update artist image: $error'),
                      ),
                    );
                    setState(() => _saving = false);
                  }
                }
              },
        child: const Text('save'),
      ),
    ],
  );
}

const playlistIcons = <String, IconData>{
  'music': Icons.music_note,
  'queue': Icons.queue_music,
  'favorite': Icons.favorite,
  'star': Icons.star,
  'car': Icons.directions_car,
  'fitness': Icons.fitness_center,
  'flight': Icons.flight,
  'celebration': Icons.celebration,
  'work': Icons.work,
  'school': Icons.school,
  'gaming': Icons.sports_esports,
  'night': Icons.nightlight,
};

class _PlaylistEditor extends StatefulWidget {
  const _PlaylistEditor({required this.playlist, required this.library});
  final PlaylistViewData playlist;
  final MusicLibrary library;
  @override
  State<_PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<_PlaylistEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.playlist.name,
  );
  String? _image;
  String? _icon;
  bool _initials = false;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _icon = widget.playlist.iconKey;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('edit playlist'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ArtworkChooser(
              path: _image ?? widget.playlist.imagePath,
              removeLabel: 'use initials',
              onChoose: () async {
                final path = await _pickImage();
                if (path != null) {
                  setState(() {
                    _image = path;
                    _icon = null;
                    _initials = false;
                  });
                }
              },
              onRemove: () => setState(() {
                _image = null;
                _icon = null;
                _initials = true;
              }),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'playlist name'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: playlistIcons.entries
                  .map(
                    (entry) => ChoiceChip(
                      label: Icon(entry.value),
                      selected: _icon == entry.key && _image == null,
                      onSelected: (_) => setState(() {
                        _icon = entry.key;
                        _image = null;
                        _initials = false;
                      }),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('cancel'),
      ),
      FilledButton(
        onPressed: _saving
            ? null
            : () async {
                setState(() => _saving = true);
                try {
                  final visual = _image != null
                      ? PlaylistVisualEdit.image(sourcePath: _image!)
                      : _icon != null
                      ? PlaylistVisualEdit.icon(key: _icon!)
                      : _initials
                      ? const PlaylistVisualEdit.initials()
                      : const PlaylistVisualEdit.keep();
                  final result = await widget.library.updatePlaylist(
                    PlaylistEditRequest(
                      playlistId: widget.playlist.id,
                      name: _name.text,
                      visual: visual,
                    ),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context, result);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('could not update playlist: $error'),
                      ),
                    );
                    setState(() => _saving = false);
                  }
                }
              },
        child: const Text('save'),
      ),
    ],
  );
}

class _ArtworkChooser extends StatelessWidget {
  const _ArtworkChooser({
    required this.path,
    required this.onChoose,
    required this.onRemove,
    this.removeLabel = 'remove image',
  });
  final String? path;
  final VoidCallback onChoose;
  final VoidCallback onRemove;
  final String removeLabel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: path != null && File(path!).existsSync()
              ? coverImg(path, 88)
              : coverImg(null, 88),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: onChoose,
                icon: const Icon(Icons.image_outlined),
                label: const Text('choose image'),
              ),
              TextButton(onPressed: onRemove, child: Text(removeLabel)),
            ],
          ),
        ),
      ],
    ),
  );
}

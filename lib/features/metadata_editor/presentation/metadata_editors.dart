import 'dart:async';

import 'package:flutter/material.dart';

import 'package:clutter/features/audio_crop/data/ffmpeg_audio_crop_service.dart';
import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';
import 'package:clutter/features/audio_crop/presentation/audio_crop_controls.dart';
import 'package:clutter/features/audio_crop/presentation/audio_crop_editor.dart';
import 'package:clutter/features/audio_crop/presentation/audio_crop_encoding_dialog.dart';
import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/metadata_editor/data/platform_artwork_picker.dart';
import 'package:clutter/features/metadata_editor/data/artwork_crop_output_store.dart';
import 'package:clutter/features/metadata_editor/domain/artwork_crop.dart';
import 'package:clutter/features/metadata_editor/domain/artwork_picker.dart';
import 'package:clutter/features/metadata_editor/presentation/widgets/artwork_chooser.dart';
import 'package:clutter/features/metadata_editor/presentation/widgets/artist_autocomplete_field.dart';

Future<SongViewData?> showSongEditor(
  BuildContext context,
  SongViewData song,
  MusicLibrary library, {
  ArtworkPicker? artworkPicker,
}) async {
  final picker = artworkPicker ?? PlatformArtworkPicker();
  final artwork = await library.getArtworkEdit(ArtworkOwner.song, song.id);
  if (!context.mounted) return null;
  return showDialog<SongViewData>(
    context: context,
    builder: (_) => _SongEditor(
      song: song,
      library: library,
      artworkPicker: picker,
      artwork: artwork,
    ),
  );
}

Future<AlbumViewData?> showAlbumEditor(
  BuildContext context,
  AlbumViewData album,
  MusicLibrary library, {
  ArtworkPicker? artworkPicker,
}) async {
  final picker = artworkPicker ?? PlatformArtworkPicker();
  final artwork = await library.getArtworkEdit(ArtworkOwner.album, album.id);
  if (!context.mounted) return null;
  return showDialog<AlbumViewData>(
    context: context,
    builder: (_) => _AlbumEditor(
      album: album,
      library: library,
      artworkPicker: picker,
      artwork: artwork,
    ),
  );
}

Future<ArtistViewData?> showArtistImageEditor(
  BuildContext context,
  ArtistViewData artist,
  MusicLibrary library, {
  ArtworkPicker? artworkPicker,
}) async {
  final picker = artworkPicker ?? PlatformArtworkPicker();
  final artwork = await library.getArtworkEdit(ArtworkOwner.artist, artist.id);
  if (!context.mounted) return null;
  return showDialog<ArtistViewData>(
    context: context,
    builder: (_) => _ArtistImageEditor(
      artist: artist,
      library: library,
      artworkPicker: picker,
      artwork: artwork,
    ),
  );
}

Future<PlaylistViewData?> showPlaylistEditor(
  BuildContext context,
  PlaylistViewData playlist,
  MusicLibrary library, {
  ArtworkPicker? artworkPicker,
}) async {
  final picker = artworkPicker ?? PlatformArtworkPicker();
  final artwork = await library.getArtworkEdit(
    ArtworkOwner.playlist,
    playlist.id,
  );
  if (!context.mounted) return null;
  return showDialog<PlaylistViewData>(
    context: context,
    builder: (_) => _PlaylistEditor(
      playlist: playlist,
      library: library,
      artworkPicker: picker,
      artwork: artwork,
    ),
  );
}

List<String> _names(String raw) => raw
    .split(',')
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toList();

const _artworkOutputs = ArtworkCropOutputStore();

CoverArtEdit _coverEdit(ArtworkCropSelection? selection, bool remove) =>
    selection?.toCoverEdit() ??
    (remove ? const CoverArtEdit.remove() : const CoverArtEdit.keep());

void _removeArtworkOutput(ArtworkCropSelection? selection) {
  if (selection != null) {
    unawaited(_artworkOutputs.remove(selection.croppedPath));
  }
}

class _SongEditor extends StatefulWidget {
  const _SongEditor({
    required this.song,
    required this.library,
    required this.artworkPicker,
    required this.artwork,
  });
  final SongViewData song;
  final MusicLibrary library;
  final ArtworkPicker artworkPicker;
  final ArtworkEditData? artwork;

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
  ArtworkCropSelection? _pickedCover;
  bool _removeCover = false;
  bool _saving = false;
  final AudioCropService _cropService = FfmpegAudioCropService();
  AudioCropSelection? _cropSelection;
  String? _preparedCropPath;
  bool _restoreOriginal = false;

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
    final prepared = _preparedCropPath;
    if (prepared != null) {
      unawaited(_cropService.removeTemporaryFile(prepared));
    }
    _removeArtworkOutput(_pickedCover);
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
      final audio = await _prepareAudioEdit();
      if (audio == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      final albumChoice = _selectedAlbumId != null
          ? AlbumChoice.existing(albumId: _selectedAlbumId!)
          : AlbumChoice.new_(
              title: _album.text,
              artists: _names(_albumArtists.text),
            );
      final cover = _coverEdit(_pickedCover, _removeCover);
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
          audio: audio,
        ),
      );
      _preparedCropPath = null;
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

  Future<SongAudioEdit?> _prepareAudioEdit() async {
    if (_restoreOriginal) return const SongAudioEdit.restoreOriginal();
    final selection = _cropSelection;
    if (selection == null) return const SongAudioEdit.keep();
    var prepared = _preparedCropPath;
    if (prepared == null) {
      prepared = await encodeAudioCrop(
        context,
        service: _cropService,
        sourcePath: _cropSourcePath,
        selection: selection,
      );
      if (prepared == null) return null;
      _preparedCropPath = prepared;
    }
    return SongAudioEdit.applyCrop(
      sourcePath: prepared,
      startMs: selection.start.inMilliseconds,
      endMs: selection.end.inMilliseconds,
    );
  }

  String get _cropSourcePath =>
      widget.song.crop?.originalAudioPath ?? widget.song.filePath;

  Future<void> _openCropEditor() async {
    final saved = widget.song.crop;
    final selection = await showAudioCropEditor(
      context,
      sourcePath: _cropSourcePath,
      service: _cropService,
      onPreviewStarted: widget.library.pause,
      initialStart: _restoreOriginal
          ? Duration.zero
          : _cropSelection?.start ??
                (saved == null ? null : Duration(milliseconds: saved.startMs)),
      initialEnd: _restoreOriginal
          ? null
          : _cropSelection?.end ??
                (saved == null ? null : Duration(milliseconds: saved.endMs)),
    );
    if (selection == null || !mounted) return;
    await _discardPreparedCrop();
    if (!mounted) return;
    final unchanged =
        saved != null &&
        selection.start.inMilliseconds == saved.startMs &&
        selection.end.inMilliseconds == saved.endMs;
    setState(() {
      _restoreOriginal = selection.isFullRange && saved != null;
      _cropSelection = selection.isFullRange || unchanged ? null : selection;
    });
  }

  Future<void> _discardPreparedCrop() async {
    final path = _preparedCropPath;
    _preparedCropPath = null;
    if (path != null) await _cropService.removeTemporaryFile(path);
  }

  Future<void> _cancel() async {
    await _discardPreparedCrop();
    if (mounted) Navigator.pop(context);
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
              ArtworkChooser(
                path: _pickedCover?.croppedPath ?? widget.song.coverPath,
                originalPath:
                    _pickedCover?.originalPath ?? widget.artwork?.originalPath,
                initialCrop: _pickedCover?.crop ?? widget.artwork?.crop,
                picker: widget.artworkPicker,
                removeLabel: 'use album artwork',
                onSelected: (selection) {
                  _removeArtworkOutput(_pickedCover);
                  setState(() {
                    _pickedCover = selection;
                    _removeCover = false;
                  });
                },
                onRemove: () => setState(() {
                  _removeArtworkOutput(_pickedCover);
                  _pickedCover = null;
                  _removeCover = true;
                }),
              ),
              if (supportsAudioCropping)
                AudioCropControls(
                  savedCropStart: widget.song.crop == null
                      ? null
                      : Duration(milliseconds: widget.song.crop!.startMs),
                  savedCropEnd: widget.song.crop == null
                      ? null
                      : Duration(milliseconds: widget.song.crop!.endMs),
                  pendingSelection: _cropSelection,
                  restorePending: _restoreOriginal,
                  onOpen: _openCropEditor,
                  onRestore: widget.song.crop == null
                      ? null
                      : () => setState(() {
                          _restoreOriginal = true;
                          _cropSelection = null;
                          unawaited(_discardPreparedCrop());
                        }),
                  onUndoRestore: () => setState(() => _restoreOriginal = false),
                ),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'title'),
              ),
              ArtistAutocompleteField(
                controller: _primary,
                searchArtists: widget.library.searchArtists,
                label: 'primary artist',
              ),
              ArtistAutocompleteField(
                controller: _features,
                searchArtists: widget.library.searchArtists,
                label: 'featured artists',
                helperText: 'separate artists with commas',
                multiple: true,
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
              ArtistAutocompleteField(
                controller: _albumArtists,
                searchArtists: widget.library.searchArtists,
                label: 'album artists',
                helperText: 'separate artists with commas',
                multiple: true,
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
          onPressed: _saving ? null : _cancel,
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
  const _AlbumEditor({
    required this.album,
    required this.library,
    required this.artworkPicker,
    required this.artwork,
  });
  final AlbumViewData album;
  final MusicLibrary library;
  final ArtworkPicker artworkPicker;
  final ArtworkEditData? artwork;

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
  ArtworkCropSelection? _pickedCover;
  bool _removeCover = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _artists.dispose();
    _removeArtworkOutput(_pickedCover);
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final cover = _coverEdit(_pickedCover, _removeCover);
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtworkChooser(
              path: _pickedCover?.croppedPath ?? widget.album.coverPath,
              originalPath:
                  _pickedCover?.originalPath ?? widget.artwork?.originalPath,
              initialCrop: _pickedCover?.crop ?? widget.artwork?.crop,
              picker: widget.artworkPicker,
              onSelected: (selection) {
                _removeArtworkOutput(_pickedCover);
                setState(() {
                  _pickedCover = selection;
                  _removeCover = false;
                });
              },
              onRemove: () => setState(() {
                _removeArtworkOutput(_pickedCover);
                _pickedCover = null;
                _removeCover = true;
              }),
            ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'album title'),
            ),
            ArtistAutocompleteField(
              controller: _artists,
              searchArtists: widget.library.searchArtists,
              label: 'album artists',
              helperText: 'separate artists with commas',
              multiple: true,
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
        child: const Text('save'),
      ),
    ],
  );
}

class _ArtistImageEditor extends StatefulWidget {
  const _ArtistImageEditor({
    required this.artist,
    required this.library,
    required this.artworkPicker,
    required this.artwork,
  });
  final ArtistViewData artist;
  final MusicLibrary library;
  final ArtworkPicker artworkPicker;
  final ArtworkEditData? artwork;
  @override
  State<_ArtistImageEditor> createState() => _ArtistImageEditorState();
}

class _ArtistImageEditorState extends State<_ArtistImageEditor> {
  ArtworkCropSelection? _picked;
  bool _remove = false;
  bool _saving = false;
  @override
  void dispose() {
    _removeArtworkOutput(_picked);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('edit ${widget.artist.name} image'),
    content: ArtworkChooser(
      path: _picked?.croppedPath ?? widget.artist.coverPath,
      originalPath: _picked?.originalPath ?? widget.artwork?.originalPath,
      initialCrop: _picked?.crop ?? widget.artwork?.crop,
      picker: widget.artworkPicker,
      removeLabel: 'use album artwork',
      onSelected: (selection) {
        _removeArtworkOutput(_picked);
        setState(() {
          _picked = selection;
          _remove = false;
        });
      },
      onRemove: () => setState(() {
        _removeArtworkOutput(_picked);
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
                  final edit = _coverEdit(_picked, _remove);
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
  const _PlaylistEditor({
    required this.playlist,
    required this.library,
    required this.artworkPicker,
    required this.artwork,
  });
  final PlaylistViewData playlist;
  final MusicLibrary library;
  final ArtworkPicker artworkPicker;
  final ArtworkEditData? artwork;
  @override
  State<_PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<_PlaylistEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.playlist.name,
  );
  ArtworkCropSelection? _image;
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
    _removeArtworkOutput(_image);
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
            ArtworkChooser(
              path: _image?.croppedPath ?? widget.playlist.imagePath,
              originalPath:
                  _image?.originalPath ?? widget.artwork?.originalPath,
              initialCrop: _image?.crop ?? widget.artwork?.crop,
              picker: widget.artworkPicker,
              removeLabel: 'use initials',
              onSelected: (selection) {
                _removeArtworkOutput(_image);
                setState(() {
                  _image = selection;
                  _icon = null;
                  _initials = false;
                });
              },
              onRemove: () => setState(() {
                _removeArtworkOutput(_image);
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
                      ? _image!.toPlaylistVisual()
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

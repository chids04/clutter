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
import 'package:clutter/features/video_import/domain/video_import_models.dart';
import 'package:clutter/shared/services/log.dart';

Future<bool> showExtractedSongEditor(
  BuildContext context,
  ExtractedAudio audio,
  MusicLibrary library, {
  ArtworkPicker? artworkPicker,
}) async {
  final picker = artworkPicker ?? PlatformArtworkPicker();
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExtractedSongEditor(
          audio: audio,
          library: library,
          artworkPicker: picker,
        ),
      ) ??
      false;
}

class _ExtractedSongEditor extends StatefulWidget {
  final ExtractedAudio audio;
  final MusicLibrary library;
  final ArtworkPicker artworkPicker;

  const _ExtractedSongEditor({
    required this.audio,
    required this.library,
    required this.artworkPicker,
  });

  @override
  State<_ExtractedSongEditor> createState() => _ExtractedSongEditorState();
}

class _ExtractedSongEditorState extends State<_ExtractedSongEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.audio.suggestedTitle,
  );
  late final TextEditingController _primary = TextEditingController(
    text: 'Unknown Artist',
  );
  late final TextEditingController _features = TextEditingController();
  late final TextEditingController _album = TextEditingController(
    text: 'Unknown Album',
  );
  late final TextEditingController _albumArtists = TextEditingController(
    text: 'Unknown Artist',
  );
  late final TextEditingController _track = TextEditingController(text: '1');
  late final TextEditingController _disc = TextEditingController(text: '1');
  late final Map<TextEditingController, String> _defaults;
  late final Map<TextEditingController, FocusNode> _defaultFocusNodes;
  final Set<TextEditingController> _usingDefaults = {};
  Timer? _debounce;
  List<AlbumViewData> _suggestions = const [];
  String? _selectedAlbumId;
  ArtworkCropSelection? _cover;
  bool _saving = false;
  final AudioCropService _cropService = FfmpegAudioCropService();
  AudioCropSelection? _cropSelection;
  String? _preparedCropPath;

  @override
  void initState() {
    super.initState();
    _defaults = {
      _title: widget.audio.suggestedTitle,
      _primary: 'Unknown Artist',
      _album: 'Unknown Album',
      _albumArtists: 'Unknown Artist',
      _track: '1',
      _disc: '1',
    };
    _usingDefaults.addAll(_defaults.keys);
    _defaultFocusNodes = {
      for (final controller in _defaults.keys)
        controller: FocusNode(debugLabel: 'video-import-default'),
    };
    for (final entry in _defaultFocusNodes.entries) {
      entry.value.addListener(
        () => _handleDefaultFocus(entry.key, entry.value),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final node in _defaultFocusNodes.values) {
      node.dispose();
    }
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
    if (_cover != null) {
      unawaited(const ArtworkCropOutputStore().remove(_cover!.croppedPath));
    }
    super.dispose();
  }

  void _handleDefaultFocus(
    TextEditingController controller,
    FocusNode focusNode,
  ) {
    if (!mounted) return;
    if (focusNode.hasFocus && _usingDefaults.contains(controller)) {
      setState(() {
        _usingDefaults.remove(controller);
        controller.clear();
        if (identical(controller, _album)) {
          _selectedAlbumId = null;
          _suggestions = const [];
        }
      });
      return;
    }
    if (!focusNode.hasFocus && controller.text.trim().isEmpty) {
      final fallback = _defaults[controller]!;
      setState(() {
        controller.value = TextEditingValue(
          text: fallback,
          selection: TextSelection.collapsed(offset: fallback.length),
        );
        _usingDefaults.add(controller);
      });
    }
  }

  FocusNode _focusNode(TextEditingController controller) =>
      _defaultFocusNodes[controller]!;

  TextStyle? _fieldStyle(
    BuildContext context,
    TextEditingController controller,
  ) => _usingDefaults.contains(controller)
      ? TextStyle(color: Theme.of(context).hintColor)
      : null;

  String _resolvedText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? _defaults[controller] ?? '' : value;
  }

  void _setExplicitValue(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _usingDefaults.remove(controller);
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
    final cropInput = await _prepareCropInput();
    if (cropInput == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final album = _selectedAlbumId == null
        ? AlbumChoice.new_(
            title: _resolvedText(_album),
            artists: _names(_resolvedText(_albumArtists)),
          )
        : AlbumChoice.existing(albumId: _selectedAlbumId!);
    try {
      await widget.library.importExtractedSong(
        ExtractedSongImportRequest(
          sourcePath: cropInput.sourcePath,
          title: _resolvedText(_title),
          primaryArtist: _resolvedText(_primary),
          featuredArtists: _names(_features.text),
          trackNum: int.tryParse(_resolvedText(_track)) ?? 1,
          discNum: int.tryParse(_resolvedText(_disc)) ?? 1,
          album: album,
          cover: _cover?.toCoverEdit() ?? const CoverArtEdit.keep(),
          crop: cropInput.crop,
        ),
      );
      _preparedCropPath = null;
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      Log.e('save extracted song failed', error);
      widget.library.showToast('could not import song');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_PreparedImportCrop?> _prepareCropInput() async {
    final selection = _cropSelection;
    if (selection == null) {
      return _PreparedImportCrop(sourcePath: widget.audio.path);
    }
    var prepared = _preparedCropPath;
    if (prepared == null) {
      prepared = await encodeAudioCrop(
        context,
        service: _cropService,
        sourcePath: widget.audio.path,
        selection: selection,
      );
      if (prepared == null) return null;
      _preparedCropPath = prepared;
    }
    return _PreparedImportCrop(
      sourcePath: prepared,
      crop: ExtractedSongCropRequest(
        originalSourcePath: widget.audio.path,
        startMs: selection.start.inMilliseconds,
        endMs: selection.end.inMilliseconds,
      ),
    );
  }

  Future<void> _openCropEditor() async {
    final selection = await showAudioCropEditor(
      context,
      sourcePath: widget.audio.path,
      service: _cropService,
      onPreviewStarted: widget.library.pause,
      initialStart: _cropSelection?.start,
      initialEnd: _cropSelection?.end,
    );
    if (selection == null || !mounted) return;
    await _discardPreparedCrop();
    if (!mounted) return;
    setState(() => _cropSelection = selection.isFullRange ? null : selection);
  }

  Future<void> _discardPreparedCrop() async {
    final path = _preparedCropPath;
    _preparedCropPath = null;
    if (path != null) await _cropService.removeTemporaryFile(path);
  }

  Future<void> _cancel() async {
    await _discardPreparedCrop();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('tag extracted audio'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtworkChooser(
              path: _cover?.croppedPath,
              originalPath: _cover?.originalPath,
              initialCrop: _cover?.crop,
              picker: widget.artworkPicker,
              onSelected: (selection) {
                final old = _cover;
                if (old != null) {
                  unawaited(
                    const ArtworkCropOutputStore().remove(old.croppedPath),
                  );
                }
                setState(() => _cover = selection);
              },
              onRemove: () {
                final old = _cover;
                if (old != null) {
                  unawaited(
                    const ArtworkCropOutputStore().remove(old.croppedPath),
                  );
                }
                setState(() => _cover = null);
              },
            ),
            if (supportsAudioCropping)
              AudioCropControls(
                savedCropStart: null,
                savedCropEnd: null,
                pendingSelection: _cropSelection,
                restorePending: false,
                onOpen: _openCropEditor,
              ),
            TextField(
              controller: _title,
              focusNode: _focusNode(_title),
              style: _fieldStyle(context, _title),
              decoration: const InputDecoration(labelText: 'title'),
            ),
            ArtistAutocompleteField(
              controller: _primary,
              focusNode: _focusNode(_primary),
              style: _fieldStyle(context, _primary),
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
              focusNode: _focusNode(_album),
              style: _fieldStyle(context, _album),
              decoration: const InputDecoration(labelText: 'album'),
              onChanged: _searchAlbums,
            ),
            if (_suggestions.isNotEmpty) _albumSuggestions(),
            ArtistAutocompleteField(
              controller: _albumArtists,
              focusNode: _focusNode(_albumArtists),
              style: _fieldStyle(context, _albumArtists),
              searchArtists: widget.library.searchArtists,
              label: 'album artists',
              helperText: 'separate artists with commas',
              multiple: true,
              onChanged: (_) => _selectedAlbumId = null,
            ),
            Row(
              children: [
                Expanded(child: _numberField(_track, 'track')),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_disc, 'disc')),
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
            : const Text('import'),
      ),
    ],
  );

  Widget _albumSuggestions() => ConstrainedBox(
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
            _setExplicitValue(_album, album.title);
            _setExplicitValue(_albumArtists, album.artists.join(', '));
            _suggestions = const [];
          }),
        );
      },
    ),
  );

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        focusNode: _focusNode(controller),
        style: _fieldStyle(context, controller),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );
}

List<String> _names(String raw) => raw
    .split(',')
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toList();

class _PreparedImportCrop {
  const _PreparedImportCrop({required this.sourcePath, this.crop});

  final String sourcePath;
  final ExtractedSongCropRequest? crop;
}

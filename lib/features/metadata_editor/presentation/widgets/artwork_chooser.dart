import 'dart:io';

import 'package:flutter/material.dart';

import 'package:clutter/features/metadata_editor/domain/artwork_crop.dart';
import 'package:clutter/features/metadata_editor/domain/artwork_picker.dart';
import 'package:clutter/features/metadata_editor/presentation/artwork_crop_editor.dart';
import 'package:clutter/features/metadata_editor/presentation/artwork_selection.dart';
import 'package:clutter/shared/presentation/cover_image.dart';
import 'package:clutter/src/rust/api/models.dart';

class ArtworkChooser extends StatefulWidget {
  const ArtworkChooser({
    super.key,
    required this.path,
    required this.picker,
    required this.onSelected,
    required this.onRemove,
    this.originalPath,
    this.initialCrop,
    this.removeLabel = 'remove image',
  });

  final String? path;
  final String? originalPath;
  final ArtworkCropRectData? initialCrop;
  final ArtworkPicker picker;
  final ValueChanged<ArtworkCropSelection> onSelected;
  final VoidCallback onRemove;
  final String removeLabel;

  @override
  State<ArtworkChooser> createState() => _ArtworkChooserState();
}

class _ArtworkChooserState extends State<ArtworkChooser> {
  bool _opening = false;

  Future<void> _choose() async {
    if (_opening) return;
    setState(() => _opening = true);
    final path = await chooseArtwork(context, picker: widget.picker);
    if (path != null && mounted) await _openCrop(path, null);
    if (mounted) setState(() => _opening = false);
  }

  Future<void> _adjust() async {
    final source = widget.originalPath ?? widget.path;
    if (source == null || _opening) return;
    setState(() => _opening = true);
    await _openCrop(source, widget.initialCrop);
    if (mounted) setState(() => _opening = false);
  }

  Future<void> _openCrop(
    String originalPath,
    ArtworkCropRectData? initialCrop,
  ) async {
    final result = await showArtworkCropEditor(
      context,
      originalPath: originalPath,
      initialCrop: initialCrop,
    );
    if (result != null && mounted) widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: widget.path != null && File(widget.path!).existsSync()
              ? coverImg(widget.path, 88)
              : coverImg(null, 88),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _opening ? null : _choose,
                icon: const Icon(Icons.image_outlined),
                label: const Text('choose image'),
              ),
              if (widget.path != null)
                OutlinedButton.icon(
                  onPressed: _opening ? null : _adjust,
                  icon: const Icon(Icons.crop),
                  label: const Text('adjust crop'),
                ),
              TextButton(
                onPressed: _opening ? null : widget.onRemove,
                child: Text(widget.removeLabel),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:clutter/features/metadata_editor/data/artwork_crop_output_store.dart';
import 'package:clutter/features/metadata_editor/domain/artwork_crop.dart';
import 'package:clutter/src/rust/api/models.dart';

Future<ArtworkCropSelection?> showArtworkCropEditor(
  BuildContext context, {
  required String originalPath,
  ArtworkCropRectData? initialCrop,
}) {
  final editor = ArtworkCropEditor(
    originalPath: originalPath,
    initialCrop: initialCrop,
  );
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (mobile) {
    return Navigator.of(context).push<ArtworkCropSelection>(
      MaterialPageRoute(builder: (_) => editor, fullscreenDialog: true),
    );
  }
  return showDialog<ArtworkCropSelection>(
    context: context,
    builder: (_) =>
        Dialog(child: SizedBox(width: 680, height: 720, child: editor)),
  );
}

class ArtworkCropEditor extends StatefulWidget {
  const ArtworkCropEditor({
    super.key,
    required this.originalPath,
    this.initialCrop,
    this.outputStore = const ArtworkCropOutputStore(),
  });

  final String originalPath;
  final ArtworkCropRectData? initialCrop;
  final ArtworkCropOutputStore outputStore;

  @override
  State<ArtworkCropEditor> createState() => _ArtworkCropEditorState();
}

class _ArtworkCropEditorState extends State<ArtworkCropEditor> {
  final CropController _controller = CropController();
  Uint8List? _image;
  Rect? _imageCrop;
  Object? _loadError;
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.originalPath).readAsBytes();
      if (mounted) setState(() => _image = bytes);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  InitialRectBuilder _initialRect() {
    final crop = widget.initialCrop;
    if (crop == null) {
      return InitialRectBuilder.withSizeAndRatio(size: 0.82, aspectRatio: 1);
    }
    return InitialRectBuilder.withArea(
      Rect.fromLTWH(crop.left, crop.top, crop.width, crop.height),
    );
  }

  void _crop() {
    if (!_ready || _imageCrop == null || _saving) return;
    setState(() => _saving = true);
    _controller.crop();
  }

  Future<void> _onCropped(CropResult result) async {
    if (result case CropSuccess(:final croppedImage)) {
      final crop = _imageCrop!;
      try {
        final path = await widget.outputStore.write(croppedImage);
        if (!mounted) {
          await widget.outputStore.remove(path);
          return;
        }
        Navigator.pop(
          context,
          ArtworkCropSelection(
            originalPath: widget.originalPath,
            croppedPath: path,
            crop: ArtworkCropRectData(
              left: crop.left,
              top: crop.top,
              width: crop.width,
              height: crop.height,
            ),
          ),
        );
        return;
      } catch (error) {
        _showError('could not save cropped image');
      }
    } else {
      _showError('could not crop image');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('crop cover art'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _saving ? null : () => Navigator.pop(context),
      ),
      actions: [
        TextButton(
          onPressed: _ready && _imageCrop != null && !_saving ? _crop : null,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('use'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: _buildBody(),
  );

  Widget _buildBody() {
    if (_loadError != null) {
      return const Center(child: Text('could not open this image'));
    }
    final image = _image;
    if (image == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('drag to position · pinch or scroll to zoom'),
        ),
        Expanded(
          child: Crop(
            image: image,
            controller: _controller,
            onCropped: _onCropped,
            onMoved: (_, imageRect) => _imageCrop = imageRect,
            onStatusChanged: (status) {
              if (mounted) setState(() => _ready = status == CropStatus.ready);
            },
            initialRectBuilder: _initialRect(),
            aspectRatio: 1,
            interactive: true,
            fixCropRect: true,
            willUpdateScale: (scale) => scale <= 8,
            maskColor: Colors.black.withValues(alpha: 0.72),
            baseColor: Colors.black,
            progressIndicator: const Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}

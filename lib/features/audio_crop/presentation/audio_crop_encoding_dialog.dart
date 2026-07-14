import 'dart:async';

import 'package:flutter/material.dart';

import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';

Future<String?> encodeAudioCrop(
  BuildContext context, {
  required AudioCropService service,
  required String sourcePath,
  required AudioCropSelection selection,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _AudioCropEncodingDialog(
    service: service,
    sourcePath: sourcePath,
    selection: selection,
  ),
);

class _AudioCropEncodingDialog extends StatefulWidget {
  const _AudioCropEncodingDialog({
    required this.service,
    required this.sourcePath,
    required this.selection,
  });

  final AudioCropService service;
  final String sourcePath;
  final AudioCropSelection selection;

  @override
  State<_AudioCropEncodingDialog> createState() =>
      _AudioCropEncodingDialogState();
}

class _AudioCropEncodingDialogState extends State<_AudioCropEncodingDialog> {
  double _progress = 0;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_encode());
  }

  Future<void> _encode() async {
    try {
      final output = await widget.service.crop(
        sourcePath: widget.sourcePath,
        selection: widget.selection,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value.clamp(0, 1));
        },
      );
      if (mounted) Navigator.pop(context, output);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    await widget.service.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('cropping audio'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 12),
        Text('${(_progress * 100).round()}%'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _cancelling ? null : _cancel,
        child: Text(_cancelling ? 'cancelling…' : 'cancel'),
      ),
    ],
  );
}

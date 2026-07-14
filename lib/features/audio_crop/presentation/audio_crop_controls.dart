import 'package:flutter/material.dart';

import 'package:clutter/features/audio_crop/application/audio_crop_controller.dart';
import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';

class AudioCropControls extends StatelessWidget {
  const AudioCropControls({
    super.key,
    required this.savedCropStart,
    required this.savedCropEnd,
    required this.pendingSelection,
    required this.restorePending,
    required this.onOpen,
    this.onRestore,
    this.onUndoRestore,
  });

  final Duration? savedCropStart;
  final Duration? savedCropEnd;
  final AudioCropSelection? pendingSelection;
  final bool restorePending;
  final VoidCallback onOpen;
  final VoidCallback? onRestore;
  final VoidCallback? onUndoRestore;

  bool get _isCropped => savedCropStart != null && savedCropEnd != null;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.content_cut, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(_statusText())),
            TextButton(onPressed: onOpen, child: const Text('crop audio')),
          ],
        ),
        if (_isCropped || restorePending) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: restorePending ? onUndoRestore : onRestore,
              icon: Icon(restorePending ? Icons.undo : Icons.restore),
              label: Text(
                restorePending ? 'undo restore' : 'restore original length',
              ),
            ),
          ),
        ],
      ],
    ),
  );

  String _statusText() {
    if (restorePending) return 'original length will be restored when saved';
    final pending = pendingSelection;
    if (pending != null) {
      return 'new crop ${formatCropTimestamp(pending.start)} – ${formatCropTimestamp(pending.end)}';
    }
    if (_isCropped) {
      return 'cropped ${formatCropTimestamp(savedCropStart!)} – ${formatCropTimestamp(savedCropEnd!)}';
    }
    return 'use part of this audio file';
  }
}

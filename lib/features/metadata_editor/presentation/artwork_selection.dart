import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:clutter/features/metadata_editor/domain/artwork_picker.dart';

Future<String?> chooseArtwork(
  BuildContext context, {
  required ArtworkPicker picker,
}) async {
  final source = picker.usesNativeSources
      ? await _showMobileArtworkSources(context)
      : ArtworkSource.files;
  if (source == null || !context.mounted) return null;

  try {
    return await picker.pick(source);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pickerErrorMessage(error))));
    }
    return null;
  }
}

Future<ArtworkSource?> _showMobileArtworkSources(BuildContext context) {
  return showModalBottomSheet<ArtworkSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('camera roll'),
            onTap: () => Navigator.pop(context, ArtworkSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('take a picture'),
            onTap: () => Navigator.pop(context, ArtworkSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

String _pickerErrorMessage(Object error) {
  if (error is! PlatformException) return 'could not choose image';
  final code = error.code.toLowerCase();
  if (code.contains('camera_access_denied')) {
    return 'camera access was denied';
  }
  if (code.contains('photo_access_denied')) {
    return 'photo library access was denied';
  }
  if (code.contains('camera') && code.contains('unavailable')) {
    return 'camera is not available';
  }
  return 'could not choose image';
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:clutter/features/metadata_editor/domain/artwork_picker.dart';

typedef DesktopArtworkPicker = Future<FilePickerResult?> Function();

class PlatformArtworkPicker implements ArtworkPicker {
  PlatformArtworkPicker({
    ImagePicker? imagePicker,
    TargetPlatform? platform,
    DesktopArtworkPicker? desktopPicker,
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _platform = platform ?? defaultTargetPlatform,
       _desktopPicker = desktopPicker ?? _pickDesktopArtwork;

  final ImagePicker _imagePicker;
  final TargetPlatform _platform;
  final DesktopArtworkPicker _desktopPicker;

  @override
  bool get usesNativeSources =>
      !kIsWeb &&
      (_platform == TargetPlatform.iOS || _platform == TargetPlatform.android);

  @override
  Future<String?> pick(ArtworkSource source) async {
    // desktop keeps the regular file browser since there is no camera roll.
    if (!usesNativeSources) return _pickFromFiles();
    if (source == ArtworkSource.files) {
      throw ArgumentError('mobile artwork needs a gallery or camera source');
    }
    // cover art does not need a full camera sensor image. this also gives ios
    // a chance to convert formats like heic before rust validates the bytes.
    final image = await _imagePicker.pickImage(
      source: source == ArtworkSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    return image?.path;
  }

  Future<String?> _pickFromFiles() async {
    final result = await _desktopPicker();
    return result?.files.single.path;
  }

  static Future<FilePickerResult?> _pickDesktopArtwork() {
    return FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      dialogTitle: 'choose artwork',
    );
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:clutter/features/video_import/domain/video_import_models.dart';

bool get supportsVideoImport =>
    !kIsWeb &&
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

class PlatformVideoPicker implements VideoPicker {
  final ImagePicker _gallery;

  PlatformVideoPicker({ImagePicker? gallery})
    : _gallery = gallery ?? ImagePicker();

  @override
  Future<SelectedVideo?> pick() async {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final video = await _gallery.pickVideo(source: ImageSource.gallery);
      return video == null
          ? null
          : SelectedVideo(path: video.path, name: video.name);
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      dialogTitle: 'choose a video',
    );
    final file = result?.files.single;
    final path = file?.path;
    return file == null || path == null
        ? null
        : SelectedVideo(path: path, name: file.name);
  }
}

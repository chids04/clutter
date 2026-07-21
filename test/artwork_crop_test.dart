import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/metadata_editor/domain/artwork_crop.dart';
import 'package:clutter/src/rust/api/models.dart';

void main() {
  test('artwork selection sends original, crop output, and crop bounds', () {
    const crop = ArtworkCropRectData(
      left: 10,
      top: 20,
      width: 200,
      height: 200,
    );
    const selection = ArtworkCropSelection(
      originalPath: '/original.jpg',
      croppedPath: '/crop.jpg',
      crop: crop,
    );

    final edit = selection.toCoverEdit() as CoverArtEdit_Replace;
    expect(edit.originalSourcePath, '/original.jpg');
    expect(edit.croppedSourcePath, '/crop.jpg');
    expect(edit.crop, crop);
  });

}

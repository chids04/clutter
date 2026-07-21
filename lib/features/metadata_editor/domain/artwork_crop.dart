import 'package:clutter/src/rust/api/models.dart';

/// the original is kept separately so another edit never crops a crop.
class ArtworkCropSelection {
  const ArtworkCropSelection({
    required this.originalPath,
    required this.croppedPath,
    required this.crop,
  });

  final String originalPath;
  final String croppedPath;
  final ArtworkCropRectData crop;

  CoverArtEdit toCoverEdit() => CoverArtEdit.replace(
    originalSourcePath: originalPath,
    croppedSourcePath: croppedPath,
    crop: crop,
  );

  PlaylistVisualEdit toPlaylistVisual() => PlaylistVisualEdit.image(
    originalSourcePath: originalPath,
    croppedSourcePath: croppedPath,
    crop: crop,
  );
}

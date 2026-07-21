enum ArtworkSource { gallery, camera, files }

abstract interface class ArtworkPicker {
  bool get usesNativeSources;

  Future<String?> pick(ArtworkSource source);
}

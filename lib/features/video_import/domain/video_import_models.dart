class SelectedVideo {
  final String path;
  final String name;

  const SelectedVideo({required this.path, required this.name});
}

class VideoMediaInfo {
  final Duration duration;
  final bool hasAudio;

  const VideoMediaInfo({required this.duration, required this.hasAudio});
}

class ExtractedAudio {
  final String path;
  final String suggestedTitle;

  const ExtractedAudio({required this.path, required this.suggestedTitle});
}

class ExtractionCancelled implements Exception {
  const ExtractionCancelled();
}

abstract interface class VideoPicker {
  Future<SelectedVideo?> pick();
}

abstract interface class AudioExtractionService {
  Future<VideoMediaInfo> inspect(String inputPath);

  Future<ExtractedAudio> extract({
    required SelectedVideo video,
    required VideoMediaInfo mediaInfo,
    required ValueChanged<double> onProgress,
  });

  Future<void> cancel();
  Future<void> removeTemporaryFile(String path);
}

typedef ValueChanged<T> = void Function(T value);

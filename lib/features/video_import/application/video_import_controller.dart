import 'package:flutter/foundation.dart';

import 'package:clutter/features/video_import/domain/video_import_models.dart';

enum VideoImportStage { inspecting, extracting, cancelling }

class VideoImportController extends ChangeNotifier {
  final AudioExtractionService extraction;

  VideoImportController(this.extraction);

  VideoImportStage _stage = VideoImportStage.inspecting;
  double? _progress;
  bool _cancelled = false;

  VideoImportStage get stage => _stage;
  double? get progress => _progress;

  Future<ExtractedAudio> extract(SelectedVideo video) async {
    // probe first so ffmpeg failures can be shown as a useful no-audio message
    final info = await extraction.inspect(video.path);
    if (_cancelled) throw const ExtractionCancelled();
    if (!info.hasAudio) throw Exception('video has no audio stream');
    _stage = VideoImportStage.extracting;
    _progress = 0;
    notifyListeners();
    final audio = await extraction.extract(
      video: video,
      mediaInfo: info,
      onProgress: (value) {
        if (_cancelled) return;
        _progress = value.clamp(0, 1);
        notifyListeners();
      },
    );
    if (_cancelled) {
      // a completion callback can race with cancel, never keep that late output
      await extraction.removeTemporaryFile(audio.path);
      throw const ExtractionCancelled();
    }
    return audio;
  }

  Future<void> cancel() async {
    _cancelled = true;
    _stage = VideoImportStage.cancelling;
    notifyListeners();
    await extraction.cancel();
  }
}

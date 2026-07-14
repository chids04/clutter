import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/video_import/application/video_import_controller.dart';
import 'package:clutter/features/video_import/data/ffmpeg_audio_extraction_service.dart';
import 'package:clutter/features/video_import/domain/video_import_models.dart';

void main() {
  test('extract inspects media and publishes bounded progress', () async {
    final service = FakeExtractionService();
    final controller = VideoImportController(service);

    final result = await controller.extract(
      const SelectedVideo(path: '/tmp/video.mp4', name: 'video.mp4'),
    );

    expect(controller.stage, VideoImportStage.extracting);
    expect(controller.progress, 1);
    expect(result.path, '/tmp/output.mp3');
    expect(service.inspectedPath, '/tmp/video.mp4');
    controller.dispose();
  });

  test('video without audio is rejected before extraction', () async {
    final service = FakeExtractionService(hasAudio: false);
    final controller = VideoImportController(service);

    await expectLater(
      controller.extract(
        const SelectedVideo(path: '/tmp/video.mp4', name: 'video.mp4'),
      ),
      throwsA(isA<Exception>()),
    );

    expect(service.extractions, 0);
    controller.dispose();
  });

  test('cancel targets the extraction service', () async {
    final service = FakeExtractionService();
    final controller = VideoImportController(service);

    await controller.cancel();

    expect(controller.stage, VideoImportStage.cancelling);
    expect(service.cancelled, isTrue);
    controller.dispose();
  });

  test('ffmpeg arguments select audio and use lame vbr quality two', () {
    final arguments = buildMp3ExtractionArguments(
      '/tmp/a video.mov',
      '/tmp/output.mp3',
    );

    expect(arguments, containsAllInOrder(['-map', '0:a:0', '-vn']));
    expect(arguments, containsAllInOrder(['-c:a', 'libmp3lame']));
    expect(arguments, containsAllInOrder(['-q:a', '2']));
    expect(arguments[2], '/tmp/a video.mov');
  });
}

class FakeExtractionService implements AudioExtractionService {
  final bool hasAudio;
  String? inspectedPath;
  int extractions = 0;
  bool cancelled = false;

  FakeExtractionService({this.hasAudio = true});

  @override
  Future<VideoMediaInfo> inspect(String inputPath) async {
    inspectedPath = inputPath;
    return VideoMediaInfo(
      duration: const Duration(seconds: 10),
      hasAudio: hasAudio,
    );
  }

  @override
  Future<ExtractedAudio> extract({
    required SelectedVideo video,
    required VideoMediaInfo mediaInfo,
    required ValueChanged<double> onProgress,
  }) async {
    extractions++;
    onProgress(1.5);
    return const ExtractedAudio(
      path: '/tmp/output.mp3',
      suggestedTitle: 'video',
    );
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> removeTemporaryFile(String path) async {}
}

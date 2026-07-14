import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_next_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_next_flutter/ffprobe_kit.dart';
import 'package:ffmpeg_kit_next_flutter/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:clutter/features/video_import/domain/video_import_models.dart';

class FfmpegAudioExtractionService implements AudioExtractionService {
  int? _sessionId;

  @override
  Future<VideoMediaInfo> inspect(String inputPath) async {
    // ffprobe gives us both an audio-stream check and a duration for progress
    final session = await FFprobeKit.getMediaInformation(inputPath);
    final information = session.getMediaInformation();
    if (information == null) {
      throw Exception('could not read the selected video');
    }
    final hasAudio = information.getStreams().any(
      (stream) => stream.getType() == 'audio',
    );
    final seconds = double.tryParse(information.getDuration() ?? '') ?? 0;
    return VideoMediaInfo(
      duration: Duration(milliseconds: (seconds * 1000).round()),
      hasAudio: hasAudio,
    );
  }

  @override
  Future<ExtractedAudio> extract({
    required SelectedVideo video,
    required VideoMediaInfo mediaInfo,
    required ValueChanged<double> onProgress,
  }) async {
    final output = await _temporaryOutput();
    // ffmpegkit completes through callbacks, wrap that session as one future
    final completion = Completer<void>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      buildMp3ExtractionArguments(video.path, output),
      (session) async {
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          if (!completion.isCompleted) completion.complete();
        } else if (ReturnCode.isCancel(code)) {
          if (!completion.isCompleted) {
            completion.completeError(const ExtractionCancelled());
          }
        } else {
          if (!completion.isCompleted) {
            completion.completeError(Exception('could not extract audio'));
          }
        }
      },
      null,
      (statistics) {
        final total = mediaInfo.duration.inMilliseconds;
        if (total > 0) {
          onProgress((statistics.getTime() / total).clamp(0, 1));
        }
      },
    );
    _sessionId = session.getSessionId();
    try {
      await completion.future;
      onProgress(1);
      return ExtractedAudio(
        path: output,
        suggestedTitle: p.basenameWithoutExtension(video.name),
      );
    } catch (_) {
      await removeTemporaryFile(output);
      rethrow;
    } finally {
      _sessionId = null;
    }
  }

  @override
  Future<void> cancel() async {
    final sessionId = _sessionId;
    if (sessionId != null) await FFmpegKit.cancel(sessionId);
  }

  @override
  Future<void> removeTemporaryFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<String> _temporaryOutput() async {
    final cache = await getTemporaryDirectory();
    final directory = Directory(p.join(cache.path, 'video-imports'));
    await directory.create(recursive: true);
    return p.join(directory.path, '${const Uuid().v4()}.mp3');
  }
}

List<String> buildMp3ExtractionArguments(String input, String output) => [
  // keep these as separate args so spaces and shell characters stay harmless
  '-y',
  '-i',
  input,
  '-map',
  '0:a:0',
  '-vn',
  '-c:a',
  'libmp3lame',
  '-q:a',
  '2',
  '-id3v2_version',
  '3',
  output,
];

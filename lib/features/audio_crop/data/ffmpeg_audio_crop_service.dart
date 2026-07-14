import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_next_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_next_flutter/ffprobe_kit.dart';
import 'package:ffmpeg_kit_next_flutter/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:clutter/features/audio_crop/domain/audio_crop_models.dart';

bool get supportsAudioCropping =>
    !kIsWeb &&
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

class FfmpegAudioCropService implements AudioCropService {
  int? _sessionId;

  @override
  Future<AudioCropInfo> inspect(String sourcePath) async {
    final probe = await FFprobeKit.getMediaInformation(sourcePath);
    final information = probe.getMediaInformation();
    final seconds = double.tryParse(information?.getDuration() ?? '') ?? 0;
    if (seconds <= 0) throw Exception('could not read audio duration');
    final waveform = await _waveform(sourcePath);
    return AudioCropInfo(
      duration: Duration(milliseconds: (seconds * 1000).round()),
      waveformPath: waveform,
    );
  }

  Future<String?> _waveform(String sourcePath) async {
    final output = await _temporaryPath('waveform', 'bmp');
    final session = await FFmpegKit.executeWithArguments(
      buildWaveformArguments(sourcePath, output),
    );
    final code = await session.getReturnCode();
    if (ReturnCode.isSuccess(code)) return output;
    await removeTemporaryFile(output);
    return null;
  }

  @override
  Future<String> crop({
    required String sourcePath,
    required AudioCropSelection selection,
    required ValueChanged<double> onProgress,
  }) async {
    final output = await _temporaryPath('crop', 'mp3');
    final completion = Completer<void>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      buildAudioCropArguments(sourcePath, output, selection),
      (session) async {
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          if (!completion.isCompleted) completion.complete();
        } else if (!completion.isCompleted) {
          completion.completeError(Exception('could not crop audio'));
        }
      },
      null,
      (statistics) {
        final total = selection.length.inMilliseconds;
        if (total > 0) {
          onProgress((statistics.getTime() / total).clamp(0, 1));
        }
      },
    );
    _sessionId = session.getSessionId();
    try {
      await completion.future;
      onProgress(1);
      return output;
    } catch (_) {
      await removeTemporaryFile(output);
      rethrow;
    } finally {
      _sessionId = null;
    }
  }

  @override
  Future<void> cancel() async {
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }

  @override
  Future<void> removeTemporaryFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<String> _temporaryPath(String prefix, String extension) async {
    final cache = await getTemporaryDirectory();
    final directory = Directory(p.join(cache.path, 'audio-crops'));
    await directory.create(recursive: true);
    return p.join(directory.path, '$prefix-${const Uuid().v4()}.$extension');
  }
}

List<String> buildWaveformArguments(String input, String output) => [
  '-y',
  '-i',
  input,
  '-filter_complex',
  'aformat=channel_layouts=mono,showwavespic=s=1200x220:colors=0x9e9e9e',
  '-frames:v',
  '1',
  '-c:v',
  'bmp',
  output,
];

List<String> buildAudioCropArguments(
  String input,
  String output,
  AudioCropSelection selection,
) => [
  '-y',
  '-ss',
  _seconds(selection.start),
  '-i',
  input,
  '-t',
  _seconds(selection.length),
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

String _seconds(Duration value) =>
    (value.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);

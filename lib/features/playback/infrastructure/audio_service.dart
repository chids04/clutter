import 'package:audio_service/audio_service.dart';

import 'package:clutter/features/playback/infrastructure/clutter_audio_handler.dart';

/// initializes the platform audio service and returns the shared handler.
///
/// call this once in `main()` before `runapp`. the returned handler can be
/// injected into [musiclibrary] so the ui and the platform media session share
/// the same playback state.
Future<ClutterAudioHandler> initAudioService() async {
  return AudioService.init(
    builder: () => ClutterAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.clutter.audio',
      androidNotificationChannelName: 'Clutter playback',
      androidNotificationOngoing: true,
    ),
  );
}

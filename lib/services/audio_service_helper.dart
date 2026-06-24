import 'package:audio_service/audio_service.dart';

import 'package:clutter/services/audio_handler.dart';

/// Initializes the platform audio service and returns the shared handler.
///
/// Call this once in `main()` before `runApp`. The returned handler can be
/// injected into [MusicLibrary] so the UI and the platform media session share
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

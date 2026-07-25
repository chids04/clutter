import 'package:audio_session/audio_session.dart';

abstract interface class PlaybackAudioSession {
  Stream<AudioInterruptionEvent> get interruptionEvents;
  Stream<void> get becomingNoisyEvents;

  Future<void> configureMusic();
  Future<bool> setActive(bool active);
}

class PlatformPlaybackAudioSession implements PlaybackAudioSession {
  final AudioSession _session;

  const PlatformPlaybackAudioSession(this._session);

  static Future<PlatformPlaybackAudioSession> create() async {
    return PlatformPlaybackAudioSession(await AudioSession.instance);
  }

  @override
  Stream<AudioInterruptionEvent> get interruptionEvents =>
      _session.interruptionEventStream;

  @override
  Stream<void> get becomingNoisyEvents => _session.becomingNoisyEventStream;

  @override
  Future<void> configureMusic() {
    return _session.configure(const AudioSessionConfiguration.music());
  }

  @override
  Future<bool> setActive(bool active) => _session.setActive(active);
}

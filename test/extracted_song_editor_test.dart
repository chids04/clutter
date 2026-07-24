import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/metadata_editor/domain/artwork_picker.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';
import 'package:clutter/features/video_import/domain/video_import_models.dart';
import 'package:clutter/features/video_import/presentation/extracted_song_editor.dart';

class _FakeLibraryRepository implements LibraryCatalogRepository {
  @override
  int getTotalSongs() => 0;

  @override
  int getTotalAlbums() => 0;

  @override
  int getTotalArtists() => 0;

  @override
  int getTotalPlaylists() => 0;

  @override
  Future<List<String>> getScanPaths() async => [];

  @override
  Future<List<PinnedItemData>> getPinnedItems() async => [];

  @override
  Future<String?> getLikedPlaylistId() async => null;

  @override
  Future<List<String>> getLikedSongIds() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlaybackPersistence implements PlaybackPersistence {
  @override
  Future<PlaybackStateData?> loadPlaybackState() async => null;

  @override
  Future<List<SongViewData>> getRecentlyPlayed(int limit) async => [];

  @override
  Future<void> recordPlay(String songId) async {}

  @override
  Future<void> savePlaybackState(
    String? songId,
    int positionMs,
    bool loopOne,
  ) async {}
}

class _FakeAudioPlayer implements AudioPlayerPort {
  @override
  Stream<PlaybackState> get playbackStateStream => const Stream.empty();

  @override
  Stream<MediaItem?> get mediaItemStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Future<void> Function()? onSkipToNext;

  @override
  Future<void> Function()? onSkipToPrevious;

  @override
  Future<void> Function()? onTrackComplete;

  @override
  Future<void> loadAndPlay(
    SongViewData song, {
    Duration? startPosition,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setLoopOne(bool loopOne) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}

class _FakeArtworkPicker implements ArtworkPicker {
  @override
  bool get usesNativeSources => false;

  @override
  Future<String?> pick(ArtworkSource source) async => null;
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  testWidgets('video import defaults clear on focus and restore when empty', (
    tester,
  ) async {
    final library = MusicLibrary(
      catalogRepository: _FakeLibraryRepository(),
      playbackPersistence: _FakePlaybackPersistence(),
      player: _FakeAudioPlayer(),
      musicDir: '/music',
    );
    await library.hydrate();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExtractedSongEditor(
                context,
                const ExtractedAudio(
                  path: '/tmp/extracted.mp3',
                  suggestedTitle: 'video title',
                ),
                library,
                artworkPicker: _FakeArtworkPicker(),
              ),
              child: const Text('open editor'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open editor'));
      await tester.pumpAndSettle();

      final defaults = <String, String>{
        'title': 'video title',
        'primary artist': 'Unknown Artist',
        'album': 'Unknown Album',
        'album artists': 'Unknown Artist',
        'track': '1',
        'disc': '1',
      };
      for (final entry in defaults.entries) {
        final field = tester.widget<TextField>(_field(entry.key));
        final hintColor = Theme.of(tester.element(_field(entry.key))).hintColor;
        expect(field.controller!.text, entry.value);
        expect(field.style?.color, hintColor);
      }

      await tester.tap(_field('title'));
      await tester.pump();
      expect(tester.widget<TextField>(_field('title')).controller!.text, '');
      expect(tester.widget<TextField>(_field('title')).style, isNull);

      await tester.tap(_field('primary artist'));
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('title')).controller!.text,
        'video title',
      );
      expect(
        tester.widget<TextField>(_field('primary artist')).controller!.text,
        '',
      );

      await tester.enterText(_field('primary artist'), 'New Artist');
      await tester.ensureVisible(_field('album'));
      await tester.pumpAndSettle();
      await tester.tap(_field('album'));
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('primary artist')).controller!.text,
        'New Artist',
      );
      expect(tester.widget<TextField>(_field('primary artist')).style, isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    }
  });
}

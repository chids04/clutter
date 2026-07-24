import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/library/presentation/widgets/song_delegate.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';

const _song = SongViewData(
  id: 'song-a',
  title: 'song a',
  primaryArtist: 'artist',
  featuredArtists: [],
  filePath: '/music/song-a.mp3',
  trackNum: 1,
  discNum: 1,
  album: 'album',
  albumId: 'album-a',
  albumArtists: ['artist'],
);

class _FakeLibraryRepository implements LibraryCatalogRepository {
  @override
  int getTotalSongs() => 1;

  @override
  int getTotalAlbums() => 0;

  @override
  int getTotalArtists() => 0;

  @override
  int getTotalPlaylists() => 0;

  @override
  Future<List<SongViewData>> getSongs(int offset, int limit) async => [_song];

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

class _RecordingAudioPlayer implements AudioPlayerPort {
  final List<SongViewData> loaded = [];

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
  Future<void> loadAndPlay(SongViewData song, {Duration? startPosition}) async {
    loaded.add(song);
  }

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

Future<({MusicLibrary library, _RecordingAudioPlayer player})>
_pumpSongDelegate(
  WidgetTester tester, {
  bool showTrackNumber = false,
  bool playing = false,
}) async {
  final player = _RecordingAudioPlayer();
  final library = MusicLibrary(
    catalogRepository: _FakeLibraryRepository(),
    playbackPersistence: _FakePlaybackPersistence(),
    player: player,
    musicDir: '/music',
  );
  await library.hydrate();
  if (playing) await library.onPlaySong(_song.id);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SongDelegate(
          song: _song,
          musicLibrary: library,
          showTrackNumber: showTrackNumber,
        ),
      ),
    ),
  );
  return (library: library, player: player);
}

Future<void> _disposeLibrary(WidgetTester tester, MusicLibrary library) async {
  await tester.pumpWidget(const SizedBox());
  library.dispose();
}

void main() {
  testWidgets('single tap starts playback without a double-tap delay', (
    tester,
  ) async {
    final result = await _pumpSongDelegate(tester);
    try {
      final rowFinder = find.byType(ListTile);

      final inkWell = tester.widget<InkWell>(
        find.ancestor(of: rowFinder, matching: find.byType(InkWell)),
      );
      expect(inkWell.onDoubleTap, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.favorite_border),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.byKey(const ValueKey('song-track-number-song-a')),
        findsNothing,
      );

      await tester.tap(find.text(_song.title));

      expect(result.player.loaded, [_song]);
    } finally {
      await _disposeLibrary(tester, result.library);
    }
  });

  testWidgets('album row shows track number to the right of playing marker', (
    tester,
  ) async {
    final result = await _pumpSongDelegate(
      tester,
      showTrackNumber: true,
      playing: true,
    );
    try {
      final status = find.byKey(const ValueKey('song-status-song-a'));
      final trackNumber = find.byKey(
        const ValueKey('song-track-number-song-a'),
      );

      expect(status, findsOneWidget);
      expect(trackNumber, findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(
        tester.getCenter(trackNumber).dx,
        greaterThan(tester.getCenter(status).dx),
      );
    } finally {
      await _disposeLibrary(tester, result.library);
    }
  });
}

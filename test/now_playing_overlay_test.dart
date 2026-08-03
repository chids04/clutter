import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';
import 'package:clutter/features/playback/presentation/now_playing_overlay.dart';

SongViewData _song(String id) => SongViewData(
  id: id,
  title: 'song $id',
  primaryArtist: 'artist $id',
  featuredArtists: const [],
  filePath: '/music/$id.mp3',
  trackNum: 1,
  discNum: 1,
  album: 'album',
  albumId: 'album-id',
  albumArtists: const ['artist'],
);

final _songs = [_song('current'), _song('a'), _song('b'), _song('c')];

class _FakeLibraryRepository implements LibraryCatalogRepository {
  @override
  int getTotalSongs() => _songs.length;

  @override
  int getTotalAlbums() => 0;

  @override
  int getTotalArtists() => 0;

  @override
  int getTotalPlaylists() => 0;

  @override
  Future<List<SongViewData>> getSongs(int offset, int limit) async => _songs;

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

Future<MusicLibrary> _pumpOverlay(
  WidgetTester tester, {
  int queuedSongs = 3,
  Size viewSize = const Size(390, 844),
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final library = MusicLibrary(
    catalogRepository: _FakeLibraryRepository(),
    playbackPersistence: _FakePlaybackPersistence(),
    player: _FakeAudioPlayer(),
    musicDir: '/music',
  );
  await library.hydrate();
  await library.onPlaySong('current');
  library.playback.addAllToQueue(_songs.skip(1).take(queuedSongs));

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: library,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-now-playing'),
              onPressed: () => showNowPlayingOverlay(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-now-playing')));
  await tester.pumpAndSettle();
  return library;
}

Future<void> _disposeLibrary(WidgetTester tester, MusicLibrary library) async {
  await tester.pumpWidget(const SizedBox());
  library.dispose();
}

void main() {
  testWidgets('expanded player centers metadata and left-hand controls', (
    tester,
  ) async {
    final library = await _pumpOverlay(tester);
    try {
      final title = tester.widget<Text>(find.text('song current'));
      final artist = tester.widget<Text>(find.text('artist current'));
      expect(title.textAlign, TextAlign.center);
      expect(artist.textAlign, TextAlign.center);

      final repeat = find.byKey(const ValueKey('now-playing-repeat'));
      final queue = find.byKey(const ValueKey('now-playing-show-queue'));
      expect(
        tester.getCenter(queue).dx,
        closeTo(tester.getCenter(repeat).dx, 0.1),
      );
      expect(
        tester.getCenter(queue).dy,
        greaterThan(tester.getCenter(repeat).dy),
      );

      final dismiss = tester.getRect(
        find.byKey(const ValueKey('now-playing-dismiss')),
      );
      expect(dismiss.left, lessThanOrEqualTo(8));
      expect(dismiss.bottom, greaterThanOrEqualTo(836));
      expect(dismiss.size, const Size(48, 48));
      expect(tester.takeException(), isNull);
    } finally {
      await _disposeLibrary(tester, library);
    }
  });

  testWidgets('queue slides up and dismisses one layer at a time', (
    tester,
  ) async {
    final library = await _pumpOverlay(tester);
    try {
      final queueLayer = find.byKey(const ValueKey('now-playing-queue-layer'));
      final queueButton = find.byKey(const ValueKey('now-playing-show-queue'));
      final dismiss = find.byKey(const ValueKey('now-playing-dismiss'));

      expect(tester.getTopLeft(queueLayer).dy, closeTo(844, 0.1));

      await tester.tap(queueButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));

      final openingTop = tester.getTopLeft(queueLayer).dy;
      expect(openingTop, greaterThan(0));
      expect(openingTop, lessThan(844));

      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.getTopLeft(queueLayer).dy, closeTo(0, 0.1));

      await tester.tap(dismiss);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final closingTop = tester.getTopLeft(queueLayer).dy;
      expect(closingTop, greaterThan(0));
      expect(closingTop, lessThan(844));

      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.getTopLeft(queueLayer).dy, closeTo(844, 0.1));
      await tester.pumpAndSettle();
      expect(find.text('song current').hitTestable(), findsOneWidget);

      await tester.tap(dismiss);
      await tester.pumpAndSettle();
      expect(dismiss, findsNothing);
    } finally {
      await _disposeLibrary(tester, library);
    }
  });

  testWidgets('queue shuffle reorders and replays its nav-style bounce', (
    tester,
  ) async {
    final library = await _pumpOverlay(tester);
    try {
      await tester.tap(find.byKey(const ValueKey('now-playing-show-queue')));
      await tester.pumpAndSettle();

      final shuffle = find.byKey(const ValueKey('shuffle-queue'));
      final scaleFinder = find.byKey(const ValueKey('shuffle-queue-scale'));
      final original = library.queue.map((song) => song.id).toList();

      await tester.tap(shuffle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));

      final compressed = tester.widget<ScaleTransition>(scaleFinder);
      expect(compressed.scale.value, lessThan(1));
      final firstShuffle = library.queue.map((song) => song.id).toList();
      expect(firstShuffle, isNot(equals(original)));

      await tester.pump(const Duration(milliseconds: 215));
      expect(
        tester.widget<ScaleTransition>(scaleFinder).scale.value,
        closeTo(1, 0.001),
      );

      await tester.tap(shuffle);
      final secondShuffle = library.queue.map((song) => song.id).toList();
      expect(secondShuffle, isNot(equals(firstShuffle)));

      library.clearQueue();
      library.playback.addToQueue(_songs[1]);
      await tester.pump();
      expect(tester.widget<IconButton>(shuffle).onPressed, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await _disposeLibrary(tester, library);
    }
  });

  testWidgets('expanded player and queue fit a wide layout', (tester) async {
    final library = await _pumpOverlay(tester, viewSize: const Size(1024, 900));
    try {
      await tester.tap(find.byKey(const ValueKey('now-playing-show-queue')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('now-playing-queue-layer')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await _disposeLibrary(tester, library);
    }
  });
}

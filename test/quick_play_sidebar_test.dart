import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';
import 'package:clutter/features/quick_play/presentation/quick_play_sidebar.dart';

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
  Future<List<SongViewData>> getSongs(int offset, int limit) async => [];

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

void main() {
  final handle = find.byKey(const ValueKey('quick-play-handle'));
  final panel = find.byKey(const ValueKey('quick-play-sidebar-panel'));

  testWidgets(
    'desktop click toggles the sidebar immediately',
    (tester) async {
      final library = await _pumpSidebar(tester);

      await tester.tap(handle);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<AnimatedPositioned>(panel).right, 0);

      await tester.pumpAndSettle();
      await tester.tap(handle);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<AnimatedPositioned>(panel).right, -280);

      await _disposeLibrary(tester, library);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'desktop mouse movement does not postpone hover opening',
    (tester) async {
      final library = await _pumpSidebar(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final center = tester.getCenter(handle);

      await mouse.addPointer(location: center);
      for (var index = 0; index < 5; index++) {
        await tester.pump(const Duration(milliseconds: 100));
        await mouse.moveTo(center + Offset(0, index.isEven ? 2 : -2));
      }

      expect(tester.widget<AnimatedPositioned>(panel).right, 0);

      await mouse.removePointer();
      await _disposeLibrary(tester, library);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'desktop pointer-down prevents hover opening during a drag',
    (tester) async {
      final library = await _pumpSidebar(tester);
      final initialTop = tester.getTopLeft(handle).dy;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);

      await mouse.addPointer(location: tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 200));
      await mouse.down(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.widget<AnimatedPositioned>(panel).right, -280);

      await mouse.moveBy(const Offset(0, 120));
      await tester.pump();

      expect(tester.getTopLeft(handle).dy, greaterThan(initialTop));
      expect(tester.widget<AnimatedPositioned>(panel).right, -280);

      await mouse.up();
      await _disposeLibrary(tester, library);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'desktop still opens after a stationary hover',
    (tester) async {
      final library = await _pumpSidebar(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);

      await mouse.addPointer(location: tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 451));

      expect(tester.widget<AnimatedPositioned>(panel).right, 0);

      await mouse.removePointer();
      await _disposeLibrary(tester, library);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'mobile supports both dragging and tapping the handle',
    (tester) async {
      final library = await _pumpSidebar(tester);
      final initialTop = tester.getTopLeft(handle).dy;

      await tester.drag(handle, const Offset(0, 120));
      await tester.pump();

      expect(tester.getTopLeft(handle).dy, greaterThan(initialTop));
      expect(tester.widget<AnimatedPositioned>(panel).right, -280);

      await tester.tap(handle);
      await tester.pump();

      expect(tester.widget<AnimatedPositioned>(panel).right, 0);

      await _disposeLibrary(tester, library);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );
}

Future<MusicLibrary> _pumpSidebar(WidgetTester tester) async {
  final library = MusicLibrary(
    catalogRepository: _FakeLibraryRepository(),
    playbackPersistence: _FakePlaybackPersistence(),
    player: _FakeAudioPlayer(),
    musicDir: '/music',
  );
  await library.hydrate();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: library,
      child: const MaterialApp(
        home: Scaffold(body: QuickPlaySidebar(child: SizedBox.expand())),
      ),
    ),
  );
  return library;
}

Future<void> _disposeLibrary(WidgetTester tester, MusicLibrary library) async {
  await tester.pumpWidget(const SizedBox());
  library.dispose();
}

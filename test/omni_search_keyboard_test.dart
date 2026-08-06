import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/app/theme.dart';
import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';
import 'package:clutter/features/search/presentation/omni_search_overlay.dart';

void main() {
  testWidgets('tab and shift-tab cycle through library search results', (
    tester,
  ) async {
    final harness = await _pumpSearch(tester);
    await _openAndSearch(tester);
    final field = find.byKey(const ValueKey('library-search-field'));

    expect(_fieldHasPrimaryFocus(tester, field), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_focusedListTileKey(), const ValueKey('library-search-playlist-p1'));
    final playlistKey = const ValueKey('library-search-playlist-p1');
    expect(
      _focusBorder(tester, playlistKey).color,
      darkTheme.colorScheme.onSurface,
    );
    expect(_focusBorder(tester, playlistKey).width, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_focusedListTileKey(), const ValueKey('library-search-album-a1'));
    expect(_focusBorder(tester, playlistKey).color, Colors.transparent);
    expect(
      _focusBorder(tester, const ValueKey('library-search-album-a1')).color,
      darkTheme.colorScheme.onSurface,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_focusedListTileKey(), const ValueKey('library-search-song-s1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_fieldHasPrimaryFocus(tester, field), isTrue);

    await _sendShiftTab(tester);
    expect(_focusedListTileKey(), const ValueKey('library-search-song-s1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(harness.library.queue, [_song]);
    expect(_focusedListTileKey(), const ValueKey('library-search-song-s1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(harness.player.loaded, [_song]);
    expect(field, findsNothing);
    await _disposeLibrary(tester, harness.library);
  });

  testWidgets('escape returns to the field before closing library search', (
    tester,
  ) async {
    final harness = await _pumpSearch(tester);
    await _openAndSearch(tester);
    final field = find.byKey(const ValueKey('library-search-field'));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(harness.library.queue, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_fieldHasPrimaryFocus(tester, field), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field, findsOneWidget);
    expect(_fieldHasPrimaryFocus(tester, field), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    await _disposeLibrary(tester, harness.library);
  });
}

Future<({MusicLibrary library, _RecordingAudioPlayer player})> _pumpSearch(
  WidgetTester tester,
) async {
  final player = _RecordingAudioPlayer();
  final library = MusicLibrary(
    catalogRepository: _FakeLibraryRepository(),
    playbackPersistence: _FakePlaybackPersistence(),
    player: player,
    musicDir: '/music',
  );
  await library.hydrate();
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: library,
      child: MaterialApp(
        theme: darkTheme,
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOmniSearchOverlay(
                context: context,
                libraryNavigatorKey: navigatorKey,
              ),
              child: const Text('open search'),
            ),
          ),
        ),
      ),
    ),
  );
  return (library: library, player: player);
}

Future<void> _openAndSearch(WidgetTester tester) async {
  await tester.tap(find.text('open search'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('library-search-field')),
    'match',
  );
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

bool _fieldHasPrimaryFocus(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).focusNode!.hasPrimaryFocus;

Key? _focusedListTileKey() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<ListTile>()
    ?.key;

BorderSide _focusBorder(WidgetTester tester, Key resultKey) {
  final frame = find.ancestor(
    of: find.byKey(resultKey),
    matching: find.byType(AnimatedContainer),
  );
  final decoration =
      tester.widget<AnimatedContainer>(frame).foregroundDecoration!
          as BoxDecoration;
  return decoration.border!.top;
}

Future<void> _sendShiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

Future<void> _disposeLibrary(WidgetTester tester, MusicLibrary library) async {
  await tester.pumpWidget(const SizedBox());
  library.dispose();
}

const _song = SongViewData(
  id: 's1',
  title: 'matching song',
  primaryArtist: 'artist',
  featuredArtists: [],
  filePath: '/music/song.mp3',
  trackNum: 1,
  discNum: 1,
  album: 'matching album',
  albumId: 'a1',
  albumArtists: ['artist'],
);

const _album = AlbumViewData(
  id: 'a1',
  title: 'matching album',
  artist: 'artist',
  songCount: 1,
  artists: ['artist'],
);

const _playlist = PlaylistViewData(
  id: 'p1',
  name: 'matching playlist',
  isSystem: false,
  songCount: 1,
);

class _FakeLibraryRepository implements LibraryCatalogRepository {
  @override
  int getTotalSongs() => 1;

  @override
  int getTotalAlbums() => 1;

  @override
  int getTotalArtists() => 0;

  @override
  int getTotalPlaylists() => 1;

  @override
  Future<List<SongViewData>> getSongs(int offset, int limit) async => [_song];

  @override
  Future<List<AlbumViewData>> getAlbums(int offset, int limit) async => [
    _album,
  ];

  @override
  Future<List<ArtistViewData>> getArtists(int offset, int limit) async => [];

  @override
  Future<List<PlaylistViewData>> getPlaylists(int offset, int limit) async => [
    _playlist,
  ];

  @override
  Future<List<SongViewData>> searchSongs(String query, int limit) async => [
    _song,
  ];

  @override
  Future<List<AlbumViewData>> searchAlbums(String query, int limit) async => [
    _album,
  ];

  @override
  Future<List<PlaylistViewData>> searchPlaylists(
    String query,
    int limit,
  ) async => [_playlist];

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
  final loaded = <SongViewData>[];

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

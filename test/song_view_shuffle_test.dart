import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/library/presentation/songs_view.dart';
import 'package:clutter/features/playback/domain/audio_player_port.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';

void main() {
  test('shuffle queues the complete library in randomized order', () async {
    final result = await _createLibrary();
    final expected = List<SongViewData>.of(_songs)..shuffle(Random(17));

    result.library.queueLibraryShuffled(random: Random(17));

    expect(
      result.library.queue.map((song) => song.id),
      expected.map((s) => s.id),
    );
    expect(result.library.currentSong, isNull);
    expect(result.player.loaded, isEmpty);
    result.library.dispose();
  });

  testWidgets('songs view shuffle button appends every library song', (
    tester,
  ) async {
    final result = await _createLibrary();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: result.library),
          Provider(create: (_) => SessionScrollPositionStore()),
        ],
        child: const MaterialApp(home: Scaffold(body: SongView())),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('shuffle-library')));
    await tester.pump();

    expect(result.library.queue, hasLength(_songs.length));
    expect(
      result.library.queue.map((song) => song.id).toSet(),
      _songs.map((song) => song.id).toSet(),
    );
    expect(result.library.currentSong, isNull);
    expect(result.player.loaded, isEmpty);

    await tester.pumpWidget(const SizedBox());
    result.library.dispose();
  });
}

Future<({MusicLibrary library, _RecordingAudioPlayer player})>
_createLibrary() async {
  final player = _RecordingAudioPlayer();
  final library = MusicLibrary(
    catalogRepository: _FakeLibraryRepository(),
    playbackPersistence: _FakePlaybackPersistence(),
    player: player,
    musicDir: '/music',
  );
  await library.hydrate();
  return (library: library, player: player);
}

final _songs = [_song('a'), _song('b'), _song('c'), _song('d')];

SongViewData _song(String id) => SongViewData(
  id: id,
  title: 'song $id',
  primaryArtist: 'artist',
  featuredArtists: const [],
  filePath: '/music/$id.mp3',
  trackNum: 1,
  discNum: 1,
  album: 'album',
  albumId: 'album-id',
  albumArtists: const ['artist'],
);

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

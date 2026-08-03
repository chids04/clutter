import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/library/presentation/artists_view.dart';
import 'package:clutter/src/rust/api/models.dart';

void main() {
  test('artist songs include primary and featured credits once', () {
    final primary = _song('primary', primaryArtist: 'Artist');
    final featured = _song(
      'featured',
      primaryArtist: 'Someone Else',
      featuredArtists: const ['ARTIST'],
    );
    final unrelated = _song('unrelated', primaryArtist: 'Another Artist');

    final songs = songsCreditingArtist(_artist, [
      primary,
      featured,
      unrelated,
      featured,
    ]);

    expect(songs.map((song) => song.id), ['primary', 'featured']);
  });

  testWidgets('artist playback actions invoke play and queue separately', (
    tester,
  ) async {
    var playCalls = 0;
    var queueCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtistPlaybackActions(
            onPlayNow: () => playCalls++,
            onQueue: () => queueCalls++,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('play now'));
    await tester.tap(find.byTooltip('add to queue'));

    expect(playCalls, 1);
    expect(queueCalls, 1);
  });

  testWidgets('artist playback actions are disabled without songs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtistPlaybackActions(onPlayNow: null, onQueue: null),
        ),
      ),
    );

    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.playlist_add_rounded),
          )
          .onPressed,
      isNull,
    );
  });
}

const _artist = ArtistViewData(
  id: 'artist-id',
  name: 'Artist',
  albumCount: 1,
  songCount: 2,
);

SongViewData _song(
  String id, {
  required String primaryArtist,
  List<String> featuredArtists = const [],
}) => SongViewData(
  id: id,
  title: id,
  primaryArtist: primaryArtist,
  featuredArtists: featuredArtists,
  filePath: '/music/$id.mp3',
  trackNum: 1,
  discNum: 1,
  album: 'album',
  albumId: 'album-id',
  albumArtists: const ['album artist'],
);

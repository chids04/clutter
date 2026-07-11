import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/playback/domain/playback_queue.dart';

SongViewData song(String id, {String? title}) => SongViewData(
  id: id,
  title: title ?? 'song $id',
  primaryArtist: 'artist',
  featuredArtists: const [],
  filePath: '/music/$id.mp3',
  trackNum: 1,
  discNum: 1,
  album: 'album',
  albumId: 'album-id',
  albumArtists: const ['artist'],
);

void main() {
  test('play next inserts at the front without losing existing songs', () {
    final queue = PlaybackQueue()
      ..addAll([song('a'), song('b')])
      ..addNext(song('next'));

    expect(queue.upNext.map((item) => item.id), ['next', 'a', 'b']);
  });

  test('reconcile replaces stale song values by id', () {
    final queue = PlaybackQueue()..add(song('a'));
    final updated = song('a', title: 'edited title');

    queue.reconcile({'a': updated});

    expect(queue.upNext.single.title, 'edited title');
  });

  test('loop snapshot is independent from later queue mutations', () {
    final queue = PlaybackQueue()
      ..add(song('next'))
      ..syncLoopSnapshot(song('current'))
      ..removeAt(0);

    expect(queue.restartLoop().map((item) => item.id), ['current', 'next']);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/models/music_library.dart';

void main() {
  test('OmniSearchResults reports empty when all groups are empty', () {
    const results = OmniSearchResults(songs: [], albums: [], playlists: []);

    expect(results.isEmpty, isTrue);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/metadata_editor/presentation/widgets/artist_autocomplete_field.dart';

void main() {
  test('primary artist suggestions replace the whole value', () {
    expect(
      applyArtistSuggestion('partial', 'Playboi Carti', multiple: false),
      'Playboi Carti',
    );
  });

  test('multi artist suggestions replace only the active name', () {
    expect(
      applyArtistSuggestion('Future, play', 'Playboi Carti', multiple: true),
      'Future, Playboi Carti',
    );
  });

  test('artist suggestions omit selected names without matching case', () {
    final filtered = filterArtistSuggestions(
      [_artist('Future'), _artist('Playboi Carti')],
      'future, pla',
      multiple: true,
    );

    expect(filtered.map((artist) => artist.name), ['Playboi Carti']);
  });

  testWidgets('a stale artist search cannot replace newer suggestions', (
    tester,
  ) async {
    final controller = TextEditingController();
    final searches = <String, Completer<List<ArtistViewData>>>{};
    Future<List<ArtistViewData>> search(String query, {int limit = 8}) {
      final completer = Completer<List<ArtistViewData>>();
      searches[query] = completer;
      return completer.future;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtistAutocompleteField(
            controller: controller,
            searchArtists: search,
            label: 'artist',
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'play');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), 'cart');
    await tester.pump(const Duration(milliseconds: 250));
    searches['cart']!.complete([_artist('Playboi Carti')]);
    await tester.pump();
    searches['play']!.complete([_artist('PlayThatBoiZay')]);
    await tester.pump();

    expect(find.text('Playboi Carti'), findsOneWidget);
    expect(find.text('PlayThatBoiZay'), findsNothing);
    controller.dispose();
  });
}

ArtistViewData _artist(String name) =>
    ArtistViewData(id: name, name: name, albumCount: 0, songCount: 0);

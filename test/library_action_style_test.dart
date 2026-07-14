import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/library/presentation/widgets/library_action_style.dart';

void main() {
  testWidgets('compact add surface keeps a full tap target', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: CompactLibraryAddSurface())),
    );

    expect(
      tester.getSize(find.byType(CompactLibraryAddSurface)),
      const Size.square(48),
    );
    final surface = tester.widget<Material>(
      find.descendant(
        of: find.byType(CompactLibraryAddSurface),
        matching: find.byType(Material),
      ),
    );
    expect(surface.color, LibraryActionStyle.background);
  });
}

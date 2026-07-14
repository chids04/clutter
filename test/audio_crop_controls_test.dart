import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/audio_crop/presentation/audio_crop_controls.dart';

void main() {
  testWidgets('saved crop presents restore original length', (tester) async {
    var restores = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioCropControls(
            savedCropStart: const Duration(seconds: 2),
            savedCropEnd: const Duration(seconds: 8),
            pendingSelection: null,
            restorePending: false,
            onOpen: () {},
            onRestore: () => restores++,
          ),
        ),
      ),
    );

    expect(find.text('restore original length'), findsOneWidget);
    await tester.tap(find.text('restore original length'));
    expect(restores, 1);
  });

  testWidgets('pending restore can be undone before save', (tester) async {
    var undos = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioCropControls(
            savedCropStart: const Duration(seconds: 2),
            savedCropEnd: const Duration(seconds: 8),
            pendingSelection: null,
            restorePending: true,
            onOpen: () {},
            onUndoRestore: () => undos++,
          ),
        ),
      ),
    );

    expect(find.textContaining('will be restored'), findsOneWidget);
    await tester.tap(find.text('undo restore'));
    expect(undos, 1);
  });
}

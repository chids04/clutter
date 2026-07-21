import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/audio_crop/presentation/audio_crop_editor.dart';

void main() {
  testWidgets('left handle moves before preview is used', (tester) async {
    var start = Duration.zero;
    var interactionsStarted = 0;
    var interactionsEnded = 0;
    await tester.pumpWidget(
      _timeline(
        start: start,
        end: const Duration(seconds: 10),
        onStartChanged: (value) => start = value,
        onInteractionStart: () => interactionsStarted++,
        onInteractionEnd: () => interactionsEnded++,
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('audio-crop-start-handle')),
      const Offset(120, 0),
    );

    expect(start, greaterThan(Duration.zero));
    expect(interactionsStarted, 1);
    expect(interactionsEnded, 1);
  });

  testWidgets('right handle moves from the full-duration edge', (tester) async {
    var end = const Duration(seconds: 10);
    await tester.pumpWidget(
      _timeline(
        start: Duration.zero,
        end: end,
        onEndChanged: (value) => end = value,
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('audio-crop-end-handle')),
      const Offset(-120, 0),
    );

    expect(end, lessThan(const Duration(seconds: 10)));
  });
}

Widget _timeline({
  required Duration start,
  required Duration end,
  ValueChanged<Duration>? onStartChanged,
  ValueChanged<Duration>? onEndChanged,
  VoidCallback? onInteractionStart,
  VoidCallback? onInteractionEnd,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 600,
        child: AudioCropTimeline(
          waveformPath: null,
          duration: const Duration(seconds: 10),
          start: start,
          end: end,
          position: Duration.zero,
          onInteractionStart: onInteractionStart ?? () {},
          onInteractionEnd: onInteractionEnd ?? () {},
          onStartChanged: onStartChanged ?? (_) {},
          onEndChanged: onEndChanged ?? (_) {},
        ),
      ),
    ),
  ),
);

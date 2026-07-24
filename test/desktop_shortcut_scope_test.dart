import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/keybindings/application/keybinding_controller.dart';
import 'package:clutter/features/keybindings/presentation/desktop_shortcut_scope.dart';
import 'package:clutter/features/keybindings/presentation/keybindings_view.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/shared/platform/desktop_platform.dart';

import 'keybinding_controller_test.dart' show FakeKeybindingRepository;

void main() {
  late KeybindingController controller;

  setUp(() async {
    controller = KeybindingController(FakeKeybindingRepository());
    await controller.load();
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('default playback keys dispatch their actions', (tester) async {
    var playPause = 0;
    final seeks = <int>[];
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      _app(
        controller,
        child: const Focus(autofocus: true, child: SizedBox()),
        onPlayPause: () => playPause++,
        onSeekBackward: (seconds) => seeks.add(-seconds),
        onSeekForward: seeks.add,
        onPrevious: () => previous++,
        onNext: () => next++,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);

    expect((playPause, previous, next), (1, 1, 1));
    expect(seeks, [-5, 5]);
  });

  testWidgets('seek shortcuts use the configured interval', (tester) async {
    final seeks = <int>[];
    await controller.updateSeekStepSeconds(12);
    await tester.pumpWidget(
      _app(
        controller,
        child: const Focus(autofocus: true, child: SizedBox()),
        onSeekBackward: (seconds) => seeks.add(-seconds),
        onSeekForward: seeks.add,
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    expect(seeks, [-12, -12, 12]);
  });

  testWidgets('primary s dispatches omni search', (tester) async {
    var searches = 0;
    await tester.pumpWidget(
      _app(
        controller,
        child: const Focus(autofocus: true, child: SizedBox()),
        onOmni: () => searches++,
      ),
    );

    final primaryKey = usesMacPrimaryModifier
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(primaryKey);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(primaryKey);

    expect(searches, 1);
  });

  testWidgets('edited binding replaces its default immediately', (
    tester,
  ) async {
    var playPause = 0;
    await controller.update(
      const KeybindingData(
        action: KeybindingAction.playPause,
        keyCode: 'key_p',
        primary: false,
        control: false,
        meta: false,
        alt: false,
        shift: false,
      ),
    );
    await tester.pumpWidget(
      _app(
        controller,
        child: const Focus(autofocus: true, child: SizedBox()),
        onPlayPause: () => playPause++,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);

    expect(playPause, 1);
  });

  testWidgets('typing in a text field never dispatches global shortcuts', (
    tester,
  ) async {
    var playPause = 0;
    final text = TextEditingController();
    await tester.pumpWidget(
      _app(
        controller,
        child: TextField(controller: text, autofocus: true),
        onPlayPause: () => playPause++,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(playPause, 0);
    text.dispose();
  });

  testWidgets('recorded keys do not leak into playback shortcuts', (
    tester,
  ) async {
    var playPause = 0;
    await tester.pumpWidget(
      _app(
        controller,
        child: const KeybindingsView(),
        onPlayPause: () => playPause++,
      ),
    );
    await tester.tap(find.text('record').first);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(playPause, 0);
    expect(controller.bindingFor(KeybindingAction.playPause)?.keyCode, 'space');
  });

  testWidgets('seek interval slider previews and persists seconds', (
    tester,
  ) async {
    await tester.pumpWidget(_app(controller, child: const KeybindingsView()));
    var slider = tester.widget<Slider>(find.byType(Slider));
    expect(
      (slider.value, slider.min, slider.max, slider.divisions),
      (5, 1, 30, 29),
    );

    slider.onChanged!(12);
    await tester.pump();
    expect(find.text('12 seconds'), findsOneWidget);

    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd!(12);
    await tester.pumpAndSettle();

    expect(controller.seekStepSeconds, 12);
  });
}

Widget _app(
  KeybindingController controller, {
  required Widget child,
  VoidCallback? onPlayPause,
  ValueChanged<int>? onSeekBackward,
  ValueChanged<int>? onSeekForward,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  VoidCallback? onOmni,
}) {
  return ChangeNotifierProvider.value(
    value: controller,
    child: MaterialApp(
      home: DesktopShortcutScope(
        onPlayPause: onPlayPause ?? () {},
        onSeekBackward: onSeekBackward ?? (_) {},
        onSeekForward: onSeekForward ?? (_) {},
        onPreviousTrack: onPrevious ?? () {},
        onNextTrack: onNext ?? () {},
        onOmniSearch: onOmni ?? () {},
        child: Scaffold(body: child),
      ),
    ),
  );
}

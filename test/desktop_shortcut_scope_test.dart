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
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      _app(
        controller,
        child: const Focus(autofocus: true, child: SizedBox()),
        onPlayPause: () => playPause++,
        onPrevious: () => previous++,
        onNext: () => next++,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);

    expect((playPause, previous, next), (1, 1, 1));
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
}

Widget _app(
  KeybindingController controller, {
  required Widget child,
  VoidCallback? onPlayPause,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  VoidCallback? onOmni,
}) {
  return ChangeNotifierProvider.value(
    value: controller,
    child: MaterialApp(
      home: DesktopShortcutScope(
        onPlayPause: onPlayPause ?? () {},
        onPreviousTrack: onPrevious ?? () {},
        onNextTrack: onNext ?? () {},
        onOmniSearch: onOmni ?? () {},
        child: Scaffold(body: child),
      ),
    ),
  );
}

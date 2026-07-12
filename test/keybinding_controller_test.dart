import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/keybindings/application/keybinding_controller.dart';
import 'package:clutter/features/keybindings/data/keybinding_repository.dart';
import 'package:clutter/features/library/domain/library_entities.dart';

KeybindingData binding(
  KeybindingAction action,
  String? code, {
  bool primary = false,
}) => KeybindingData(
  action: action,
  keyCode: code,
  primary: primary,
  control: false,
  meta: false,
  alt: false,
  shift: false,
);

class FakeKeybindingRepository implements KeybindingRepository {
  List<KeybindingData> values = [
    binding(KeybindingAction.playPause, 'space'),
    binding(KeybindingAction.previousTrack, 'key_h'),
    binding(KeybindingAction.nextTrack, 'key_l'),
    binding(KeybindingAction.omniSearch, 'key_s', primary: true),
  ];
  Object? updateError;

  @override
  Future<List<KeybindingData>> getAll() async => List.from(values);

  @override
  Future<List<KeybindingData>> reset() async {
    values = [
      binding(KeybindingAction.playPause, 'space'),
      binding(KeybindingAction.previousTrack, 'key_h'),
      binding(KeybindingAction.nextTrack, 'key_l'),
      binding(KeybindingAction.omniSearch, 'key_s', primary: true),
    ];
    return List.from(values);
  }

  @override
  Future<KeybindingData> update(KeybindingData value) async {
    if (updateError case final error?) throw error;
    values = [
      for (final current in values)
        if (current.action == value.action) value else current,
    ];
    return value;
  }
}

void main() {
  test('loads, updates, and clears bindings through the repository', () async {
    final repository = FakeKeybindingRepository();
    final controller = KeybindingController(repository);
    await controller.load();

    await controller.update(binding(KeybindingAction.playPause, 'key_p'));
    expect(controller.labelFor(KeybindingAction.playPause), 'p');

    await controller.clear(KeybindingAction.playPause);
    expect(controller.labelFor(KeybindingAction.playPause), 'unbound');
    controller.dispose();
  });

  test('failed conflict update leaves controller state unchanged', () async {
    final repository = FakeKeybindingRepository();
    final controller = KeybindingController(repository);
    await controller.load();
    repository.updateError = Exception(
      'keybinding already used by previous_track',
    );

    await expectLater(
      controller.update(binding(KeybindingAction.nextTrack, 'key_h')),
      throwsException,
    );

    expect(controller.labelFor(KeybindingAction.nextTrack), 'l');
    controller.dispose();
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:clutter/features/keybindings/data/keybinding_repository.dart';
import 'package:clutter/features/keybindings/domain/key_code_codec.dart';
import 'package:clutter/features/library/domain/library_entities.dart';

class KeybindingController extends ChangeNotifier {
  final KeybindingRepository repository;

  KeybindingController(this.repository);

  List<KeybindingData> _bindings = const [];
  int _seekStepSeconds = 5;
  bool _isLoading = false;

  List<KeybindingData> get bindings => List.unmodifiable(_bindings);
  int get seekStepSeconds => _seekStepSeconds;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _bindings = await repository.getAll();
      _seekStepSeconds = await repository.getSeekStepSeconds();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  KeybindingData? bindingFor(KeybindingAction action) {
    return _bindings.where((binding) => binding.action == action).firstOrNull;
  }

  KeybindingAction? actionFor(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
    return _bindings
        .where((binding) => KeyCodeCodec.matches(binding, event))
        .map((binding) => binding.action)
        .firstOrNull;
  }

  Future<void> update(KeybindingData binding) async {
    final updated = await repository.update(binding);
    _replace(updated);
  }

  Future<void> clear(KeybindingAction action) async {
    await update(
      KeybindingData(
        action: action,
        primary: false,
        control: false,
        meta: false,
        alt: false,
        shift: false,
      ),
    );
  }

  Future<void> updateSeekStepSeconds(int seconds) async {
    _seekStepSeconds = await repository.updateSeekStepSeconds(seconds);
    notifyListeners();
  }

  Future<void> reset() async {
    _bindings = await repository.reset();
    _seekStepSeconds = 5;
    notifyListeners();
  }

  String labelFor(KeybindingAction action) {
    final binding = bindingFor(action);
    return binding == null ? 'unbound' : KeyCodeCodec.label(binding);
  }

  void _replace(KeybindingData updated) {
    _bindings = [
      for (final binding in _bindings)
        if (binding.action == updated.action) updated else binding,
    ];
    notifyListeners();
  }
}

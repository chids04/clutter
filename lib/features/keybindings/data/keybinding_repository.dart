import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/src/rust/api/library.dart';

abstract interface class KeybindingRepository {
  Future<List<KeybindingData>> getAll();
  Future<int> getSeekStepSeconds();
  Future<KeybindingData> update(KeybindingData binding);
  Future<int> updateSeekStepSeconds(int seconds);
  Future<List<KeybindingData>> reset();
}

class RustKeybindingRepository implements KeybindingRepository {
  final LibraryApi _api;

  const RustKeybindingRepository(this._api);

  @override
  Future<List<KeybindingData>> getAll() => _api.getKeybindings();

  @override
  Future<int> getSeekStepSeconds() => _api.getSeekStepSeconds();

  @override
  Future<KeybindingData> update(KeybindingData binding) =>
      _api.updateKeybinding(binding: binding);

  @override
  Future<int> updateSeekStepSeconds(int seconds) =>
      _api.updateSeekStepSeconds(seconds: seconds);

  @override
  Future<List<KeybindingData>> reset() => _api.resetKeybindings();
}

import 'dart:collection';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:clutter/features/library/application/library_catalog_controller.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/shared/services/log.dart';

/// keeps platform folder selection and scan progress away from catalog state.
///
/// the catalog controller is injected because a completed scan must refresh
/// the rust-backed cache before the ui is told that scanning has finished.
class LibraryScanController extends ChangeNotifier {
  final LibraryCatalogRepository repository;
  final LibraryCatalogController catalog;
  final String musicDirectory;

  LibraryScanController({
    required this.repository,
    required this.catalog,
    required this.musicDirectory,
  });

  final List<String> _directories = [];
  final Set<String> _directorySet = {};
  bool _isScanning = false;

  UnmodifiableListView<String> get directories =>
      UnmodifiableListView(_directories);
  bool get isScanning => _isScanning;
  bool get usesSandboxMusicFolder =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> hydrate() async {
    final paths = await repository.getScanPaths();
    for (final path in paths) {
      if (_directorySet.add(path)) _directories.add(path);
    }
    notifyListeners();
  }

  Future<int> add(String directory) async {
    if (!_directorySet.add(directory)) return 0;
    _directories.add(directory);
    final before = catalog.totalSongs;
    await _scan(directory);
    return catalog.totalSongs - before;
  }

  Future<int> rescan(String directory) async {
    if (!_directorySet.contains(directory) || _isScanning) return 0;
    final before = catalog.totalSongs;
    await _scan(directory);
    return catalog.totalSongs - before;
  }

  Future<void> setOnly(String directory) async {
    if (_isScanning) return;
    for (final oldPath in List<String>.from(_directories)) {
      if (oldPath == directory) continue;
      try {
        await repository.deleteScanPath(oldPath);
      } catch (error) {
        Log.e('delete old scan path failed for $oldPath', error);
      }
    }
    _directories
      ..clear()
      ..add(directory);
    _directorySet
      ..clear()
      ..add(directory);
    await catalog.reloadAll();
    await rescan(directory);
  }

  Future<int> remove(String directory) async {
    if (!_directorySet.contains(directory)) return 0;
    final removed = await repository.deleteScanPath(directory);
    _directorySet.remove(directory);
    _directories.remove(directory);
    await catalog.reloadAll();
    notifyListeners();
    return removed;
  }

  Future<void> reset() async {
    _directories.clear();
    _directorySet.clear();
    await repository.resetLibrary();
    await catalog.reloadAll();
    notifyListeners();
  }

  Future<String?> chooseDirectory() async {
    if (usesSandboxMusicFolder) return musicDirectory;
    try {
      return await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'select directory to scan for music',
      );
    } on PlatformException catch (error) {
      Log.e('unsupported file picker op', error);
      return null;
    }
  }

  Future<void> _scan(String directory) async {
    if (_isScanning) return;
    _isScanning = true;
    // notify before awaiting so progress indicators appear straight away
    notifyListeners();
    try {
      await repository.scanDirectory(directory);
      await catalog.reloadAll();
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }
}

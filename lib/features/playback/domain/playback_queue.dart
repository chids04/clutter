import 'dart:collection';
import 'dart:math';

import 'package:clutter/features/library/domain/library_entities.dart';

// this is mutable on purpose; the controller owns it and exposes readonly views
class PlaybackQueue {
  final List<SongViewData> _upNext = [];
  final List<SongViewData> _history = [];
  final List<SongViewData> _loopSnapshot = [];

  UnmodifiableListView<SongViewData> get upNext =>
      UnmodifiableListView(_upNext);
  bool get hasNext => _upNext.isNotEmpty;
  bool get hasPrevious => _history.isNotEmpty;

  void add(SongViewData song) => _upNext.add(song);
  void addAll(Iterable<SongViewData> songs) => _upNext.addAll(songs);
  void addNext(SongViewData song) => _upNext.insert(0, song);
  SongViewData takeNext() => _upNext.removeAt(0);
  void remember(SongViewData song) => _history.add(song);
  SongViewData takePrevious() => _history.removeLast();

  void move(int from, int to) {
    if (from == to) return;
    final item = _upNext.removeAt(from);
    _upNext.insert(to, item);
  }

  bool shuffle({Random? random}) {
    if (_upNext.length < 2) return false;

    final previousOrder = [for (final song in _upNext) song.id];
    _upNext.shuffle(random);
    if (!_hasOrder(previousOrder)) return true;

    final firstDifferentIndex = _upNext.indexWhere(
      (song) => song.id != _upNext.first.id,
    );
    if (firstDifferentIndex == -1) return false;

    final first = _upNext.first;
    _upNext[0] = _upNext[firstDifferentIndex];
    _upNext[firstDifferentIndex] = first;
    return true;
  }

  void removeAt(int index) => _upNext.removeAt(index);

  void removeIds(Set<String> ids) {
    _upNext.removeWhere((song) => ids.contains(song.id));
    _history.removeWhere((song) => ids.contains(song.id));
    _loopSnapshot.removeWhere((song) => ids.contains(song.id));
  }

  void syncLoopSnapshot(SongViewData? current) {
    _loopSnapshot
      ..clear()
      ..addAll([?current, ..._upNext]);
  }

  List<SongViewData> restartLoop() => List.unmodifiable(_loopSnapshot);

  void replaceQueue(Iterable<SongViewData> songs) {
    _upNext
      ..clear()
      ..addAll(songs);
  }

  void reconcile(Map<String, SongViewData> byId) {
    _replaceKnown(_upNext, byId);
    _replaceKnown(_history, byId);
    _replaceKnown(_loopSnapshot, byId);
  }

  void clear() {
    _upNext.clear();
    _loopSnapshot.clear();
  }

  void reset() {
    _upNext.clear();
    _history.clear();
    _loopSnapshot.clear();
  }

  void _replaceKnown(List<SongViewData> songs, Map<String, SongViewData> byId) {
    for (var index = 0; index < songs.length; index++) {
      songs[index] = byId[songs[index].id] ?? songs[index];
    }
  }

  bool _hasOrder(List<String> songIds) {
    for (var index = 0; index < songIds.length; index++) {
      if (_upNext[index].id != songIds[index]) return false;
    }
    return true;
  }
}

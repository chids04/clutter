import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:clutter/features/remote_sources/data/sftp_credential_store.dart';
import 'package:clutter/features/remote_sources/data/sftp_repository.dart';
import 'package:clutter/src/rust/api/models.dart';

class SftpDownloadJob {
  final String label;
  final SftpDownloadProgressData progress;

  const SftpDownloadJob({required this.label, required this.progress});

  String get jobId => progress.jobId;

  bool get isTerminal => switch (progress.state) {
    SftpDownloadStateData.completed ||
    SftpDownloadStateData.completedWithErrors ||
    SftpDownloadStateData.cancelled ||
    SftpDownloadStateData.failed => true,
    _ => false,
  };

  SftpDownloadJob withProgress(SftpDownloadProgressData next) =>
      SftpDownloadJob(label: label, progress: next);
}

class SftpController extends ChangeNotifier {
  final SftpRepository repository;
  final SftpCredentialStore credentials;
  final Future<void> Function() onLibraryChanged;

  SftpController({
    required this.repository,
    required this.credentials,
    required this.onLibraryChanged,
  });

  List<SftpProfileData> _profiles = const [];
  List<SftpEntryData> _entries = const [];
  final Map<String, SftpDownloadJob> _jobs = {};
  final Map<String, StreamSubscription<SftpDownloadProgressData>>
  _jobSubscriptions = {};
  SftpProfileData? _selectedProfile;
  String _currentPath = '';
  String? _error;
  bool _loading = false;
  bool _connected = false;

  UnmodifiableListView<SftpProfileData> get profiles =>
      UnmodifiableListView(_profiles);
  UnmodifiableListView<SftpEntryData> get entries =>
      UnmodifiableListView(_entries);
  UnmodifiableListView<SftpDownloadJob> get jobs =>
      UnmodifiableListView(_jobs.values);
  SftpProfileData? get selectedProfile => _selectedProfile;
  String get currentPath => _currentPath;
  String? get error => _error;
  bool get loading => _loading;
  bool get connected => _connected;

  Future<void> hydrate() async {
    try {
      await _guard(() async {
        _profiles = await repository.getProfiles();
        _selectedProfile = _profiles
            .where((item) => item.isSelected)
            .firstOrNull;
        _selectedProfile ??= _profiles.firstOrNull;
        if (_selectedProfile != null) await connectSelected();
      });
    } catch (_) {
      // the stored error is rendered by the view and retry stays available
    }
  }

  Future<String> probeFingerprint(String host, int port) =>
      repository.probeFingerprint(host.trim(), port);

  Future<SftpProfileData> saveProfile({
    required SftpProfileData profile,
    required String password,
  }) async {
    await repository.testConnection(profile, password);
    final existing = _profiles
        .where((item) => item.id == profile.id)
        .firstOrNull;
    final previousPassword = existing == null
        ? null
        : await credentials.readPassword(existing.id);
    final saved = await repository.saveProfile(profile);
    try {
      await credentials.writePassword(saved.id, password);
    } catch (_) {
      await _rollbackSave(saved, existing, previousPassword);
      rethrow;
    }
    await repository.selectProfile(saved.id);
    await _reloadProfiles(selectedId: saved.id);
    await connectSelected();
    return saved;
  }

  Future<void> _rollbackSave(
    SftpProfileData saved,
    SftpProfileData? existing,
    String? previousPassword,
  ) async {
    if (existing == null) {
      await repository.deleteProfile(saved.id);
      return;
    }
    await repository.saveProfile(existing);
    if (previousPassword != null) {
      await credentials.writePassword(existing.id, previousPassword);
    }
  }

  Future<void> selectProfile(String profileId) async {
    await _guard(() async {
      await repository.selectProfile(profileId);
      await _reloadProfiles(selectedId: profileId);
      _currentPath = '';
      _entries = const [];
      await connectSelected();
    });
  }

  Future<void> deleteProfile(String profileId) async {
    await _guard(() async {
      await repository.deleteProfile(profileId);
      await credentials.deletePassword(profileId);
      await _reloadProfiles();
      _selectedProfile = _profiles.firstOrNull;
      if (_selectedProfile case final profile?) {
        await repository.selectProfile(profile.id);
        await _reloadProfiles(selectedId: profile.id);
      }
      _currentPath = '';
      _entries = const [];
      _connected = false;
      if (_selectedProfile != null) await connectSelected();
    });
  }

  Future<void> connectSelected() async {
    final profile = _selectedProfile;
    if (profile == null) return;
    final password = await credentials.readPassword(profile.id);
    if (password == null || password.isEmpty) {
      throw StateError('saved password is missing');
    }
    await repository.connect(profile.id, password);
    _connected = true;
    await browse('');
  }

  Future<void> browse(String relativePath) async {
    final profile = _selectedProfile;
    if (profile == null) return;
    await _guard(() async {
      _entries = await repository.browse(profile.id, relativePath);
      _currentPath = relativePath;
    });
  }

  Future<void> startDownload(SftpEntryData entry) async {
    final profile = _selectedProfile;
    if (profile == null) return;
    await _guard(() async {
      final initial = await repository.startDownload(
        profile.id,
        entry.relativePath,
        entry.kind == SftpEntryKindData.directory,
      );
      _jobs[initial.jobId] = SftpDownloadJob(
        label: entry.name,
        progress: initial,
      );
      _watchJob(initial.jobId);
    });
  }

  void _watchJob(String jobId) {
    _jobSubscriptions[jobId] = repository
        .watchDownload(jobId)
        .listen(
          (progress) async {
            final job = _jobs[jobId];
            if (job == null) return;
            _jobs[jobId] = job.withProgress(progress);
            if (_isTerminal(progress.state)) {
              _jobs.removeWhere(
                (candidateId, candidate) =>
                    candidateId != jobId && candidate.isTerminal,
              );
            }
            notifyListeners();
            if (!_isTerminal(progress.state)) return;
            await _jobSubscriptions.remove(jobId)?.cancel();
            if (progress.filesCompleted > 0) await onLibraryChanged();
            if (_connected) await browse(_currentPath);
          },
          onError: (Object error) {
            _error = error.toString();
            notifyListeners();
          },
        );
  }

  Future<void> cancelDownload(String jobId) => repository.cancelDownload(jobId);

  Future<void> _reloadProfiles({String? selectedId}) async {
    _profiles = await repository.getProfiles();
    _selectedProfile = selectedId == null
        ? _profiles.where((item) => item.isSelected).firstOrNull
        : _profiles.where((item) => item.id == selectedId).firstOrNull;
  }

  Future<void> _guard(Future<void> Function() operation) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await operation();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  bool _isTerminal(SftpDownloadStateData state) => switch (state) {
    SftpDownloadStateData.completed ||
    SftpDownloadStateData.completedWithErrors ||
    SftpDownloadStateData.cancelled ||
    SftpDownloadStateData.failed => true,
    _ => false,
  };

  @override
  void dispose() {
    for (final subscription in _jobSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    if (_selectedProfile case final profile?) {
      unawaited(repository.disconnect(profile.id));
    }
    super.dispose();
  }
}

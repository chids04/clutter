import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/features/remote_sources/data/sftp_credential_store.dart';
import 'package:clutter/features/remote_sources/data/sftp_repository.dart';
import 'package:clutter/src/rust/api/models.dart';

void main() {
  test('a failed vault write removes a newly-created rust profile', () async {
    final repository = FakeSftpRepository();
    final credentials = FakeSftpCredentials()..failWrites = true;
    final controller = SftpController(
      repository: repository,
      credentials: credentials,
      onLibraryChanged: () async {},
    );

    await expectLater(
      controller.saveProfile(
        profile: _profile(id: ''),
        password: 'secret',
      ),
      throwsStateError,
    );

    expect(repository.deletedProfiles, ['generated']);
    controller.dispose();
  });

  test(
    'a completed download refreshes the library and current folder',
    () async {
      final repository = FakeSftpRepository();
      final credentials = FakeSftpCredentials();
      var refreshes = 0;
      repository.profiles = [_profile(id: 'home')];
      credentials.passwords['home'] = 'secret';
      final controller = SftpController(
        repository: repository,
        credentials: credentials,
        onLibraryChanged: () async => refreshes++,
      );
      await controller.hydrate();

      await controller.startDownload(
        const SftpEntryData(
          name: 'song.mp3',
          relativePath: 'song.mp3',
          kind: SftpEntryKindData.file,
          downloaded: false,
        ),
      );
      repository.downloads.add(_progress(SftpDownloadStateData.completed));
      await Future<void>.delayed(Duration.zero);

      expect(refreshes, 1);
      expect(repository.browsedPaths.last, '');
      await repository.downloads.close();
      controller.dispose();
    },
  );
}

SftpProfileData _profile({required String id}) => SftpProfileData(
  id: id,
  name: 'home',
  host: '100.64.0.1',
  port: 22,
  username: 'music',
  rootPath: '/music',
  hostKeyFingerprint: 'SHA256:test',
  isSelected: true,
);

SftpDownloadProgressData _progress(SftpDownloadStateData state) =>
    SftpDownloadProgressData(
      jobId: 'job',
      state: state,
      filesCompleted: state == SftpDownloadStateData.completed ? 1 : 0,
      filesTotal: 1,
      bytesCompleted: BigInt.one,
      bytesTotal: BigInt.one,
      failedFiles: 0,
    );

class FakeSftpCredentials implements SftpCredentialStore {
  final passwords = <String, String>{};
  bool failWrites = false;

  @override
  Future<void> deletePassword(String profileId) async {
    passwords.remove(profileId);
  }

  @override
  Future<String?> readPassword(String profileId) async => passwords[profileId];

  @override
  Future<void> writePassword(String profileId, String password) async {
    if (failWrites) throw StateError('vault unavailable');
    passwords[profileId] = password;
  }
}

class FakeSftpRepository implements SftpRepository {
  List<SftpProfileData> profiles = [];
  final deletedProfiles = <String>[];
  final browsedPaths = <String>[];
  final downloads = StreamController<SftpDownloadProgressData>();

  @override
  Future<List<SftpEntryData>> browse(
    String profileId,
    String relativePath,
  ) async {
    browsedPaths.add(relativePath);
    return [];
  }

  @override
  Future<void> cancelDownload(String jobId) async {}

  @override
  Future<void> connect(String profileId, String password) async {}

  @override
  Future<void> deleteProfile(String profileId) async {
    deletedProfiles.add(profileId);
    profiles.removeWhere((profile) => profile.id == profileId);
  }

  @override
  Future<void> disconnect(String profileId) async {}

  @override
  Future<List<SftpProfileData>> getProfiles() async => profiles;

  @override
  Future<String> probeFingerprint(String host, int port) async => 'SHA256:test';

  @override
  Future<SftpProfileData> saveProfile(SftpProfileData profile) async {
    final saved = SftpProfileData(
      id: profile.id.isEmpty ? 'generated' : profile.id,
      name: profile.name,
      host: profile.host,
      port: profile.port,
      username: profile.username,
      rootPath: profile.rootPath,
      hostKeyFingerprint: profile.hostKeyFingerprint,
      isSelected: profile.isSelected,
    );
    profiles = [saved];
    return saved;
  }

  @override
  Future<void> selectProfile(String profileId) async {}

  @override
  Future<void> testConnection(SftpProfileData profile, String password) async {}

  @override
  Future<SftpDownloadProgressData> startDownload(
    String profileId,
    String relativePath,
    bool recursive,
  ) async => _progress(SftpDownloadStateData.discovering);

  @override
  Stream<SftpDownloadProgressData> watchDownload(String jobId) =>
      downloads.stream;
}

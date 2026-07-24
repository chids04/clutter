import 'package:clutter/src/rust/api/library.dart';
import 'package:clutter/src/rust/api/models.dart';

abstract interface class SftpRepository {
  Future<List<SftpProfileData>> getProfiles();
  Future<SftpProfileData> saveProfile(SftpProfileData profile);
  Future<void> deleteProfile(String profileId);
  Future<void> selectProfile(String profileId);
  Future<String> probeFingerprint(String host, int port);
  Future<void> connect(String profileId, String password);
  Future<void> testConnection(SftpProfileData profile, String password);
  Future<void> disconnect(String profileId);
  Future<List<SftpEntryData>> browse(String profileId, String relativePath);
  Future<SftpDownloadProgressData> startDownload(
    String profileId,
    String relativePath,
    bool recursive,
  );
  Stream<SftpDownloadProgressData> watchDownload(String jobId);
  Future<void> cancelDownload(String jobId);
}

// this adapter keeps frb naming and generated types away from the controller
class RustSftpRepository implements SftpRepository {
  final LibraryApi _api;

  const RustSftpRepository(this._api);

  @override
  Future<List<SftpProfileData>> getProfiles() => _api.getSftpProfiles();

  @override
  Future<SftpProfileData> saveProfile(SftpProfileData profile) =>
      _api.saveSftpProfile(profile: profile);

  @override
  Future<void> deleteProfile(String profileId) =>
      _api.deleteSftpProfile(profileId: profileId);

  @override
  Future<void> selectProfile(String profileId) =>
      _api.selectSftpProfile(profileId: profileId);

  @override
  Future<String> probeFingerprint(String host, int port) =>
      _api.probeSftpFingerprint(host: host, port: port);

  @override
  Future<void> connect(String profileId, String password) =>
      _api.connectSftp(profileId: profileId, password: password);

  @override
  Future<void> testConnection(SftpProfileData profile, String password) =>
      _api.testSftpConnection(profile: profile, password: password);

  @override
  Future<void> disconnect(String profileId) =>
      _api.disconnectSftp(profileId: profileId);

  @override
  Future<List<SftpEntryData>> browse(String profileId, String relativePath) =>
      _api.browseSftp(profileId: profileId, relativePath: relativePath);

  @override
  Future<SftpDownloadProgressData> startDownload(
    String profileId,
    String relativePath,
    bool recursive,
  ) => _api.startSftpDownload(
    profileId: profileId,
    relativePath: relativePath,
    recursive: recursive,
  );

  @override
  Stream<SftpDownloadProgressData> watchDownload(String jobId) =>
      _api.watchSftpDownload(jobId: jobId);

  @override
  Future<void> cancelDownload(String jobId) =>
      _api.cancelSftpDownload(jobId: jobId);
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SftpCredentialStore {
  Future<String?> readPassword(String profileId);
  Future<void> writePassword(String profileId, String password);
  Future<void> deletePassword(String profileId);
}

// dart only owns this adapter because keychain and keystore are flutter plugins
class PlatformSftpCredentialStore implements SftpCredentialStore {
  static const _prefix = 'clutter.sftp.password.';
  final FlutterSecureStorage _storage;

  const PlatformSftpCredentialStore([
    // unsigned macos development builds use the regular keychain. the data
    // protection keychain requires a development signing identity.
    this._storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  ]);

  String _key(String profileId) => '$_prefix$profileId';

  @override
  Future<String?> readPassword(String profileId) =>
      _storage.read(key: _key(profileId));

  @override
  Future<void> writePassword(String profileId, String password) =>
      _storage.write(key: _key(profileId), value: password);

  @override
  Future<void> deletePassword(String profileId) =>
      _storage.delete(key: _key(profileId));
}

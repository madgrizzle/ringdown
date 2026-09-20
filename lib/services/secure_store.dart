import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _serverUrl = 'server_url';
  static const _accessToken = 'access_token';
  static const _refreshToken = 'refresh_token';
  static const _username = 'username';

  Future<String?> readServerUrl() => _storage.read(key: _serverUrl);
  Future<void> writeServerUrl(String url) =>
      _storage.write(key: _serverUrl, value: url);

  Future<String?> readAccessToken() => _storage.read(key: _accessToken);
  Future<void> writeAccessToken(String token) =>
      _storage.write(key: _accessToken, value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshToken);
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshToken, value: token);

  Future<String?> readUsername() => _storage.read(key: _username);
  Future<void> writeUsername(String username) =>
      _storage.write(key: _username, value: username);

  Future<void> clearSession() async {
    await _storage.delete(key: _accessToken);
    await _storage.delete(key: _refreshToken);
  }

  Future<void> clearAll() => _storage.deleteAll();
}

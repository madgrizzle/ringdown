import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: androidOptions,
              iOptions: iosOptions,
            );

  final FlutterSecureStorage _storage;

  // Any other FlutterSecureStorage instance in the app -- including the one
  // the background FCM isolate builds in notifications.dart -- MUST use
  // these same platform options. Different options (e.g. the
  // encryptedSharedPreferences default of false vs. true here) make Android
  // read/write a genuinely different underlying file, so a second instance
  // built with different options silently reads back null instead of the
  // token this instance wrote, rather than throwing.
  static const androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);
  static const iosOptions =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  // Public so other isolates (background FCM handling) read/write the same
  // keys without risking a typo'd duplicate literal.
  static const accessTokenKey = 'access_token';
  static const refreshTokenKey = 'refresh_token';

  static const _accessToken = accessTokenKey;
  static const _refreshToken = refreshTokenKey;
  static const _username = 'username';
  static const _deviceId = 'device_id';

  Future<String?> readAccessToken() => _storage.read(key: _accessToken);
  Future<void> writeAccessToken(String token) =>
      _storage.write(key: _accessToken, value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshToken);
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshToken, value: token);

  Future<String?> readUsername() => _storage.read(key: _username);
  Future<void> writeUsername(String username) =>
      _storage.write(key: _username, value: username);

  /// Stable id for this install. A new sign-in replaces the previous session
  /// for the same id, so one phone does not pile up sessions.
  Future<String> readOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final id = List<int>.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _deviceId, value: id);
    return id;
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessToken);
    await _storage.delete(key: _refreshToken);
  }

  Future<void> clearAll() => _storage.deleteAll();
}

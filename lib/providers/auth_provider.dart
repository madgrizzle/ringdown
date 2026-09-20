import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_state.dart';
import '../services/api_client.dart';
import '../services/notifications.dart';
import '../services/prefs_store.dart';
import '../services/secure_store.dart';
import 'settings_provider.dart';

class AuthNotifier extends Notifier<AuthState> {
  bool _handlingUnauthorized = false;

  SecureStore get _secure => ref.read(secureStoreProvider);
  PrefsStore get _prefs => ref.read(prefsStoreProvider);
  ApiClient get _api => ref.read(apiClientProvider);
  NotificationService get _notify => ref.read(notificationServiceProvider);

  @override
  AuthState build() {
    Future.microtask(restore);
    return AuthState.unknown;
  }

  Future<void> restore() async {
    String? url;
    String? token;
    String? lastUser;
    try {
      url = await _secure.readServerUrl();
      token = await _secure.readAccessToken();
      lastUser = await _secure.readUsername() ?? _prefs.readLastUsername();
    } catch (e) {
      state = const AuthState(status: AuthStatus.needsServer);
      return;
    }
    if (url == null || url.isEmpty) {
      state = AuthState(
        status: AuthStatus.needsServer,
        lastUsername: lastUser,
      );
      return;
    }
    if (token == null || token.isEmpty) {
      state = AuthState(
        status: AuthStatus.needsLogin,
        serverUrl: url,
        lastUsername: lastUser,
      );
      return;
    }
    state = AuthState(
      status: AuthStatus.authenticated,
      serverUrl: url,
      token: token,
      lastUsername: lastUser,
    );
    try {
      final me = await _api.me();
      state = state.copyWith(
        username: me.username,
        inboxEmail: me.inboxEmail,
        lastUsername: me.username,
      );
      await _registerPush();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await handleUnauthorized();
      } else {
        // Keep the session; list screen will show cached/offline.
        state = state.copyWith(lastUsername: lastUser);
      }
    } catch (_) {
      state = state.copyWith(lastUsername: lastUser);
    }
  }

  void changeServer() {
    state = AuthState(
      status: AuthStatus.needsServer,
      serverUrl: state.serverUrl,
      lastUsername: state.lastUsername ?? state.username,
    );
  }

  Future<void> saveServerUrl(String raw) async {
    final url = ApiClient.normalizeBaseUrl(raw);
    await _api.checkHealth(url);
    await _secure.writeServerUrl(url);
    final lastUser =
        await _secure.readUsername() ?? _prefs.readLastUsername();
    state = AuthState(
      status: AuthStatus.needsLogin,
      serverUrl: url,
      lastUsername: lastUser,
    );
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final tokens = await _api.login(username: username, password: password);
    await _secure.writeAccessToken(tokens.accessToken);
    if (tokens.refreshToken != null &&
        tokens.refreshToken != 'refresh-not-implemented') {
      await _secure.writeRefreshToken(tokens.refreshToken!);
    }
    await _secure.writeUsername(username);
    await _prefs.writeLastUsername(username);
    state = AuthState(
      status: AuthStatus.authenticated,
      serverUrl: state.serverUrl,
      token: tokens.accessToken,
      username: username,
      lastUsername: username,
    );
    try {
      final me = await _api.me();
      state = state.copyWith(
        username: me.username,
        inboxEmail: me.inboxEmail,
      );
    } catch (_) {}
    await _registerPush();
  }

  Future<void> logout() async {
    await _secure.clearSession();
    state = AuthState(
      status: AuthStatus.needsLogin,
      serverUrl: state.serverUrl,
      lastUsername: state.lastUsername ?? state.username,
    );
  }

  Future<void> handleUnauthorized() async {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      if (state.status == AuthStatus.needsLogin) return;
      await _secure.clearSession();
      state = AuthState(
        status: AuthStatus.needsLogin,
        serverUrl: state.serverUrl,
        lastUsername: state.lastUsername ?? state.username,
      );
    } finally {
      _handlingUnauthorized = false;
    }
  }

  Future<void> registerPush() => _registerPush();

  Future<void> _registerPush() async {
    try {
      await _notify.requestPermissionAndRegister((token, platform) {
        return _api.registerDevice(fcmToken: token, platform: platform);
      });
    } catch (e) {
      // Push is best-effort; login still succeeds.
    }
  }
}

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    token: () => ref.read(authProvider).token,
    baseUrl: () => ref.read(authProvider).serverUrl,
    onUnauthorized: () {
      ref.read(authProvider.notifier).handleUnauthorized();
    },
  );
});

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Notification / deep-link target applied after login.
final pendingAlarmIdProvider = StateProvider<int?>((ref) => null);

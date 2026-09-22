import 'dart:io';

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
    String? token;
    String? refresh;
    String? lastUser;
    try {
      token = await _secure.readAccessToken();
      refresh = await _secure.readRefreshToken();
      lastUser = await _secure.readUsername() ?? _prefs.readLastUsername();
    } catch (e) {
      state = const AuthState(
        status: AuthStatus.needsLogin,
        serverUrl: ApiClient.defaultBaseUrl,
      );
      return;
    }
    if ((token == null || token.isEmpty) &&
        (refresh == null || refresh.isEmpty)) {
      state = AuthState(
        status: AuthStatus.needsLogin,
        serverUrl: ApiClient.defaultBaseUrl,
        lastUsername: lastUser,
      );
      return;
    }
    state = AuthState(
      status: AuthStatus.authenticated,
      serverUrl: ApiClient.defaultBaseUrl,
      token: token,
      refreshToken: refresh,
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
        state = state.copyWith(lastUsername: lastUser);
      }
    } catch (_) {
      state = state.copyWith(lastUsername: lastUser);
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final deviceId = await _secure.readOrCreateDeviceId();
    final ios = Platform.isIOS;
    final tokens = await _api.login(
      username: username,
      password: password,
      deviceId: deviceId,
      deviceName: ios ? 'iOS' : 'Android',
      platform: ios ? 'ios' : 'android',
    );
    await applyTokens(
      access: tokens.accessToken,
      refresh: tokens.refreshToken,
    );
    await _secure.writeUsername(username);
    await _prefs.writeLastUsername(username);
    state = state.copyWith(
      status: AuthStatus.authenticated,
      serverUrl: ApiClient.defaultBaseUrl,
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
    final refresh = state.refreshToken;
    String? fcm;
    try {
      fcm = await _notify.currentFcmToken();
    } catch (_) {}
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await _api.logout(refreshToken: refresh, fcmToken: fcm);
      } catch (_) {}
    }
    await _secure.clearSession();
    state = AuthState(
      status: AuthStatus.needsLogin,
      serverUrl: ApiClient.defaultBaseUrl,
      lastUsername: state.lastUsername ?? state.username,
    );
  }

  Future<void> applyTokens({required String access, String? refresh}) async {
    await _secure.writeAccessToken(access);
    if (refresh != null &&
        refresh.isNotEmpty &&
        refresh != 'refresh-not-implemented') {
      await _secure.writeRefreshToken(refresh);
    }
    state = state.copyWith(
      token: access,
      refreshToken: refresh ?? state.refreshToken,
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
        serverUrl: ApiClient.defaultBaseUrl,
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
    refreshToken: () => ref.read(authProvider).refreshToken,
    baseUrl: () => ApiClient.defaultBaseUrl,
    onTokens: (access, refresh) {
      return ref.read(authProvider.notifier).applyTokens(
            access: access,
            refresh: refresh,
          );
    },
    onUnauthorized: () {
      ref.read(authProvider.notifier).handleUnauthorized();
    },
  );
});

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Notification / deep-link target applied after login.
final pendingAlarmIdProvider = StateProvider<int?>((ref) => null);

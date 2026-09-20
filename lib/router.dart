import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/auth_state.dart';
import 'providers/auth_provider.dart';
import 'screens/alarm_detail_screen.dart';
import 'screens/alarm_list_screen.dart';
import 'screens/login_screen.dart';
import 'screens/server_url_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';

class _AuthRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh();
  ref.listen<AuthState>(authProvider, (prev, next) {
    if (prev?.status != next.status) refresh.ping();
  });

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (auth.status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }
      if (loc == '/splash') {
        return switch (auth.status) {
          AuthStatus.needsServer => '/server',
          AuthStatus.needsLogin => '/login',
          AuthStatus.authenticated => () {
              final id = ref.read(pendingAlarmIdProvider);
              if (id != null) {
                ref.read(pendingAlarmIdProvider.notifier).state = null;
                return '/alarms/$id';
              }
              return '/alarms';
            }(),
          AuthStatus.unknown => '/splash',
        };
      }
      switch (auth.status) {
        case AuthStatus.needsServer:
          return loc == '/server' ? null : '/server';
        case AuthStatus.needsLogin:
          return loc == '/login' ? null : '/login';
        case AuthStatus.authenticated:
          if (loc == '/login' || loc == '/server' || loc == '/splash') {
            final id = ref.read(pendingAlarmIdProvider);
            if (id != null) {
              ref.read(pendingAlarmIdProvider.notifier).state = null;
              return '/alarms/$id';
            }
            return '/alarms';
          }
          return null;
        case AuthStatus.unknown:
          return '/splash';
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/server', builder: (context, state) => const ServerUrlScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/alarms',
        builder: (context, state) => const AlarmListScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return AlarmDetailScreen(alarmId: id);
            },
          ),
        ],
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    ],
  );
});

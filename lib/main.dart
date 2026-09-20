import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/auth_state.dart';
import 'providers/alarms_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/ticker_provider.dart';
import 'router.dart';
import 'services/prefs_store.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    ],
  );

  final notifications = container.read(notificationServiceProvider);
  await notifications.init();
  notifications.onRefresh = () {
    container.read(alarmsProvider.notifier).silentRefresh();
  };
  notifications.onTap = (id) {
    container.read(pendingAlarmIdProvider.notifier).state = id;
    if (container.read(authProvider).status == AuthStatus.authenticated) {
      container.read(routerProvider).go('/alarms/$id');
    }
  };
  notifications.onAck = (id) {
    container.read(alarmsProvider.notifier).ackOne(id);
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const RingdownApp(),
    ),
  );
}

class RingdownApp extends ConsumerStatefulWidget {
  const RingdownApp({super.key});

  @override
  ConsumerState<RingdownApp> createState() => _RingdownAppState();
}

class _RingdownAppState extends ConsumerState<RingdownApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ticker = ref.read(tickerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      ticker.resume();
      ref.read(alarmsProvider.notifier).silentRefresh();
      ref.read(alarmsProvider.notifier).drainAckQueue();
      ref.read(notificationServiceProvider).consumeNativePendingAck();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ticker.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(settingsProvider).themeMode;
    return MaterialApp.router(
      title: 'Ringdown',
      theme: ringdownTheme(Brightness.light),
      darkTheme: ringdownTheme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../acknowledgements.dart';
import '../priority_category.dart';
import 'ack_queue.dart';
import 'api_client.dart';

const nmsAlarmsChannelId = 'nms_alarms';
const nmsAlarmCategory = 'NMS_ALARM';
const ackActionId = 'ACK';
const summaryNotificationId = 900001;
const summaryPayload = 'summary';

const _settingsChannel = MethodChannel('ringdown/settings');
const _notifyChannel = MethodChannel('ringdown/notifications');

typedef AlarmTapCallback = void Function(int alarmId);
typedef AlarmAckCallback = void Function(int alarmId);
typedef RefreshCallback = void Function();
typedef SummaryTapCallback = void Function();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // A `notification` payload is already shown by the OS. Showing another
  // local notification is what produced duplicate banners.
  final id = alarmIdFromData(message.data);
  final status = message.data['status']?.toString();
  final state = message.data['state']?.toString();
  final cleared = status == 'N' || state == 'cleared';
  if (!isSummaryMessage(message.data) &&
      id != null &&
      !kShowAcknowledgements &&
      !cleared) {
    await ackFromBackground(id, onlyQueueWhenOffline: true);
  }
  if (message.notification != null) return;
  await NotificationService.showLocalFromMessage(message);
}

@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  final id = _alarmIdFromResponse(response);
  if (id != null && response.actionId == ackActionId) {
    ackFromBackground(id);
  }
}

@pragma('vm:entry-point')
Future<void> ackFromBackground(
  int alarmId, {
  bool onlyQueueWhenOffline = false,
}) async {
  try {
    const storage = FlutterSecureStorage();
    var access = await storage.read(key: 'access_token');
    var refresh = await storage.read(key: 'refresh_token');
    if ((access == null || access.isEmpty) &&
        (refresh == null || refresh.isEmpty)) {
      await _enqueue(alarmId);
      return;
    }
    final dio = ApiClient(
      token: () => access,
      refreshToken: () => refresh,
      baseUrl: () => ApiClient.defaultBaseUrl,
      onTokens: (newAccess, newRefresh) async {
        access = newAccess;
        refresh = newRefresh;
        await storage.write(key: 'access_token', value: newAccess);
        await storage.write(key: 'refresh_token', value: newRefresh);
      },
      onUnauthorized: () {},
    );
    try {
      await dio.ack(alarmId);
    } on ApiException catch (e) {
      if (onlyQueueWhenOffline) {
        if (e.statusCode == null) await _enqueue(alarmId);
      } else {
        await _enqueue(alarmId);
      }
    } catch (_) {
      await _enqueue(alarmId);
    }
  } catch (_) {
    await _enqueue(alarmId);
  }
}

Future<void> _enqueue(int alarmId) async {
  final prefs = await SharedPreferences.getInstance();
  await AckQueue(prefs).enqueue(alarmId);
}

int? _alarmIdFromResponse(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null) return null;
  return int.tryParse(payload);
}

bool isSummaryMessage(Map<String, dynamic> data) =>
    data['summary']?.toString() == '1';

int? alarmIdFromData(Map<String, dynamic> data) {
  final raw = data['alarm_id']?.toString();
  if (raw == null) return null;
  return int.tryParse(raw);
}

class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  AlarmTapCallback? onTap;
  SummaryTapCallback? onSummary;
  AlarmAckCallback? onAck;
  AlarmAckCallback? onIncomingAlarm;
  RefreshCallback? onRefresh;

  bool firebaseReady = false;
  bool _initialized = false;
  final Completer<void> _ready = Completer<void>();

  Future<void> get ready => _ready.future;

  Future<void> init() async {
    if (_initialized) {
      await ready;
      return;
    }
    _initialized = true;
    try {
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_ringdown');
    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          nmsAlarmCategory,
          actions: [
            if (kShowAcknowledgements)
              DarwinNotificationAction.plain(ackActionId, 'ACK'),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
    );

    await ensureAlarmChannel();

    try {
      await Firebase.initializeApp();
      firebaseReady = true;
      if (Platform.isIOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((message) async {
        onRefresh?.call();
        final deliveredId = alarmIdFromData(message.data);
        final status = message.data['status']?.toString();
        final state = message.data['state']?.toString();
        final cleared = status == 'N' || state == 'cleared';
        if (!isSummaryMessage(message.data) &&
            deliveredId != null &&
            !kShowAcknowledgements &&
            !cleared) {
          onIncomingAlarm?.call(deliveredId);
        }
        // iOS presents the APNs banner via AppDelegate.willPresent. Showing
        // another local notification would duplicate it.
        if (Platform.isIOS && message.notification != null) return;
        await showLocalFromMessage(message, plugin: _plugin);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _openMessage(message.data);
      });
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (initial != null) {
        _openMessage(initial.data);
      }
    } catch (e) {
      debugPrint('Firebase not configured: $e');
      firebaseReady = false;
    }

    _notifyChannel.setMethodCallHandler((call) async {
      if (call.method == 'ack') {
        final id = int.tryParse(call.arguments?.toString() ?? '');
        if (id != null) onAck?.call(id);
      } else if (call.method == 'open') {
        final id = int.tryParse(call.arguments?.toString() ?? '');
        if (id != null) onTap?.call(id);
      }
      return null;
    });

    await consumeNativePendingAck();
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  void _openMessage(Map<String, dynamic> data) {
    if (isSummaryMessage(data)) {
      onSummary?.call();
      return;
    }
    final id = alarmIdFromData(data);
    if (id != null) onTap?.call(id);
  }

  void _onResponse(NotificationResponse response) {
    if (response.payload == summaryPayload) {
      onSummary?.call();
      return;
    }
    final id = _alarmIdFromResponse(response);
    if (id == null) return;
    if (response.actionId == ackActionId) {
      onAck?.call(id);
    } else {
      onTap?.call(id);
    }
  }

  Future<void> consumeNativePendingAck() async {
    try {
      final raw = await _notifyChannel.invokeMethod<String>('takePendingAck');
      final id = int.tryParse(raw ?? '');
      if (id != null) onAck?.call(id);
    } catch (_) {}
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> ensureAlarmChannel() async {
    await _androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        nmsAlarmsChannelId,
        'NMS Alarms',
        description: 'Telenium NMS alarm notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  /// Android 13+ runtime permission. Independent of Firebase.
  Future<bool> requestAndroidNotifications() async {
    if (!Platform.isAndroid) return true;
    await ensureAlarmChannel();
    final requested = await _androidPlugin?.requestNotificationsPermission();
    if (requested == true) return true;
    return await _androidPlugin?.areNotificationsEnabled() ?? false;
  }

  /// Request permission, then register the FCM token. Returns false if denied.
  Future<bool> requestPermissionAndRegister(
    Future<void> Function(String token, String platform) register,
  ) async {
    try {
      await ready.timeout(const Duration(seconds: 15));
    } catch (_) {
      debugPrint('Notification service not ready');
    }
    if (Platform.isAndroid) {
      final androidOk = await requestAndroidNotifications();
      if (!androidOk) return false;
    }
    if (!firebaseReady) return false;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: true,
      criticalAlert: true,
    );
    final allowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!allowed) return false;

    if (Platform.isIOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final token = await _fcmToken(messaging);
    if (token != null) {
      final platform = Platform.isIOS ? 'ios' : 'android';
      await register(token, platform);
    }
    messaging.onTokenRefresh.listen((t) async {
      final platform = Platform.isIOS ? 'ios' : 'android';
      try {
        await register(t, platform);
      } catch (e) {
        debugPrint('FCM token refresh register failed: $e');
      }
    });
    return token != null;
  }

  Future<String?> currentFcmToken() async {
    if (!firebaseReady) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  /// iOS requires an APNs token before FCM will issue a registration token.
  Future<String?> _fcmToken(FirebaseMessaging messaging) async {
    if (Platform.isIOS) {
      for (var i = 0; i < 20; i++) {
        final apns = await messaging.getAPNSToken();
        if (apns != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    try {
      return await messaging.getToken();
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
      return null;
    }
  }

  static Future<void> showLocalFromMessage(
    RemoteMessage message, {
    FlutterLocalNotificationsPlugin? plugin,
  }) async {
    final local = plugin ?? FlutterLocalNotificationsPlugin();
    final data = message.data;
    if (isSummaryMessage(data)) {
      final title = data['title']?.toString() ??
          '${data['count'] ?? ''} other alarms in the last 20 seconds';
      final body = data['body']?.toString() ?? 'Open the app to review them';
      final android = AndroidNotificationDetails(
        nmsAlarmsChannelId,
        'NMS Alarms',
        channelDescription: 'Telenium NMS alarm notifications',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@drawable/ic_stat_ringdown',
        tag: 'other-alarms',
      );
      final darwin = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        threadIdentifier: 'other-alarms',
      );
      await local.show(
        summaryNotificationId,
        title,
        body,
        NotificationDetails(android: android, iOS: darwin),
        payload: summaryPayload,
      );
      return;
    }
    final id = alarmIdFromData(data);
    if (id == null) return;
    final inAlarm = data['status'] == 'Y' || data['state'] == 'active';
    final title = message.notification?.title ??
        data['title'] ??
        '${data['site_id'] ?? ''}: ${data['description'] ?? ''}';
    final body = message.notification?.body ??
        data['body'] ??
        '${data['device'] ?? ''} — ${inAlarm ? 'Active' : 'Cleared'}';

    final priority = int.tryParse(data['priority']?.toString() ?? '') ?? 20;
    final accent = colorFromHex(data['color']?.toString()) ??
        priorityCategory(priority).color;
    final android = AndroidNotificationDetails(
      nmsAlarmsChannelId,
      'NMS Alarms',
      channelDescription: 'Telenium NMS alarm notifications',
      importance: inAlarm ? Importance.high : Importance.defaultImportance,
      priority: inAlarm ? Priority.high : Priority.defaultPriority,
      icon: '@drawable/ic_stat_ringdown',
      color: accent,
      tag: id.toString(),
      category: AndroidNotificationCategory.alarm,
      actions: kShowAcknowledgements
          ? const [
              AndroidNotificationAction(
                ackActionId,
                'ACK',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ]
          : const <AndroidNotificationAction>[],
    );
    final darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      interruptionLevel:
          inAlarm ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
      categoryIdentifier: nmsAlarmCategory,
      threadIdentifier: data['site_id']?.toString() ?? '',
    );
    await local.show(
      id,
      title,
      body,
      NotificationDetails(android: android, iOS: darwin),
      payload: id.toString(),
    );
  }

  /// Opens system notification settings.
  ///
  /// If Android notifications are still disabled, opens the *app* notification
  /// screen (master "Show notifications" switch). Opening the channel page
  /// while the app is blocked is what produces "At your request, Android is
  /// blocking this category of notifications".
  Future<void> openNotificationSettings() async {
    try {
      if (Platform.isAndroid) {
        final enabled = await requestAndroidNotifications();
        if (enabled) {
          await _settingsChannel.invokeMethod('openNotificationChannel');
        } else {
          await _settingsChannel.invokeMethod('openAppNotificationSettings');
        }
      } else {
        await _settingsChannel.invokeMethod('openAppSettings');
      }
    } catch (e) {
      debugPrint('openNotificationSettings: $e');
    }
  }
}

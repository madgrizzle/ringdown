import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ack_queue.dart';
import 'api_client.dart';

const nmsAlarmsChannelId = 'nms_alarms';
const nmsAlarmCategory = 'NMS_ALARM';
const ackActionId = 'ACK';

const _settingsChannel = MethodChannel('ringdown/settings');
const _notifyChannel = MethodChannel('ringdown/notifications');

typedef AlarmTapCallback = void Function(int alarmId);
typedef AlarmAckCallback = void Function(int alarmId);
typedef RefreshCallback = void Function();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
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
Future<void> ackFromBackground(int alarmId) async {
  try {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');
    final url = await storage.read(key: 'server_url');
    if (token == null || url == null) {
      await _enqueue(alarmId);
      return;
    }
    final dio = ApiClient(
      token: () => token,
      baseUrl: () => url,
      onUnauthorized: () {},
    );
    try {
      await dio.ack(alarmId);
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
  AlarmAckCallback? onAck;
  RefreshCallback? onRefresh;

  bool firebaseReady = false;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_ringdown');
    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          nmsAlarmCategory,
          actions: [
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

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
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

    try {
      await Firebase.initializeApp();
      firebaseReady = true;
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((message) async {
        onRefresh?.call();
        await showLocalFromMessage(message, plugin: _plugin);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final id = alarmIdFromData(message.data);
        if (id != null) onTap?.call(id);
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        final id = alarmIdFromData(initial.data);
        if (id != null) onTap?.call(id);
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
  }

  void _onResponse(NotificationResponse response) {
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

  /// Request permission, then register the FCM token. Returns false if denied.
  Future<bool> requestPermissionAndRegister(
    Future<void> Function(String token, String platform) register,
  ) async {
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

    final token = await messaging.getToken();
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
    return true;
  }

  static Future<void> showLocalFromMessage(
    RemoteMessage message, {
    FlutterLocalNotificationsPlugin? plugin,
  }) async {
    final local = plugin ?? FlutterLocalNotificationsPlugin();
    final data = message.data;
    final id = alarmIdFromData(data);
    if (id == null) return;
    final inAlarm = data['status'] == 'Y' || data['state'] == 'active';
    final title = message.notification?.title ??
        '${data['site_id'] ?? ''}: ${data['description'] ?? ''}';
    final body = message.notification?.body ??
        '${data['device'] ?? ''} — ${inAlarm ? 'Active' : 'Cleared'}';

    final android = AndroidNotificationDetails(
      nmsAlarmsChannelId,
      'NMS Alarms',
      channelDescription: 'Telenium NMS alarm notifications',
      importance: inAlarm ? Importance.high : Importance.defaultImportance,
      priority: inAlarm ? Priority.high : Priority.defaultPriority,
      icon: '@drawable/ic_stat_ringdown',
      tag: id.toString(),
      category: AndroidNotificationCategory.alarm,
      actions: [
        const AndroidNotificationAction(
          ackActionId,
          'ACK',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
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

  Future<void> openNotificationSettings() async {
    try {
      if (Platform.isAndroid) {
        await _settingsChannel.invokeMethod('openNotificationChannel');
      } else {
        await _settingsChannel.invokeMethod('openAppSettings');
      }
    } catch (e) {
      debugPrint('openNotificationSettings: $e');
    }
  }
}

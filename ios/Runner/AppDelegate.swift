import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let notifyChannelName = "ringdown/notifications"
  private let settingsChannelName = "ringdown/settings"
  private var notifyChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let ack = UNNotificationAction(
      identifier: "ACK",
      title: "ACK",
      options: []
    )
    let category = UNNotificationCategory(
      identifier: "NMS_ALARM",
      actions: [ack],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])

    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // UIScene startup can skip plugin didFinishLaunching; register APNs here
    // so FirebaseMessaging.getToken() has an APNs token on iOS.
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return ok
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    notifyChannel = FlutterMethodChannel(name: notifyChannelName, binaryMessenger: messenger)
    notifyChannel?.setMethodCallHandler { call, result in
      if call.method == "takePendingAck" {
        let id = UserDefaults.standard.string(forKey: "pending_notification_ack")
        UserDefaults.standard.removeObject(forKey: "pending_notification_ack")
        result(id)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let settings = FlutterMethodChannel(name: settingsChannelName, binaryMessenger: messenger)
    settings.setMethodCallHandler { call, result in
      if call.method == "openAppSettings" {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
          result(nil)
        } else {
          result(FlutterError(code: "no_url", message: nil, details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Default iOS behavior hides alerts while the app is in the foreground.
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let alarmId = (info["alarm_id"] as? String)
      ?? (info["alarm_id"] as? NSNumber)?.stringValue

    if response.actionIdentifier == "ACK", let alarmId {
      UserDefaults.standard.set(alarmId, forKey: "pending_notification_ack")
      notifyChannel?.invokeMethod("ack", arguments: alarmId)
    } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier, let alarmId {
      notifyChannel?.invokeMethod("open", arguments: alarmId)
    }

    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}

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
    UNUserNotificationCenter.current().delegate = self

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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "ringdown.native")?.messenger() else {
      return
    }

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

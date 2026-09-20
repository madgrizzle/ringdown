# Ringdown

Flutter mobile app for field technicians. It talks only to the public NMS Alert Gateway technician API — not the admin UI.

Technicians configure a server URL, sign in, receive high-priority FCM alarms for their own inbox, and acknowledge from the list, the detail screen, or the system notification.

## Features

- Dark-first Material 3 list of this technician’s alarms
- Hide cleared by default; two live timers (active + unacked) that freeze correctly
- One-tap ACK on the card, swipe, detail, storm banner, site group, multi-select, and notification action
- Filter / sort / group-by on the list, persisted
- Offline cache + queued ACKs
- FCM on Android and iOS (`nms_alarms` channel, `NMS_ALARM` category)

## Run

```bash
cd ringdown
flutter pub get
dart run flutter_launcher_icons
flutter run
```

First launch asks for the gateway URL (example `https://api.phionalerter.com`) and checks `GET /health`.

## Firebase (push)

Push is optional for browsing the list, required for lock-screen / killed-state delivery.

1. Create a Firebase project that matches the gateway’s Admin SDK credentials.
2. Android: add `android/app/google-services.json`. The Gradle plugin is applied automatically when that file exists.
3. iOS: add `ios/Runner/GoogleService-Info.plist`, enable Push Notifications and Background Modes → Remote notifications on the App ID, and upload an **APNs Authentication Key** in the Firebase console. Without the APNs key, FCM “succeeds” and the iPhone gets nothing.
4. Enable Time Sensitive Notifications on the iOS App ID so in-alarm alerts can break Focus.

The app registers `POST /devices/register` after login, only if notification permission is granted.

## Package id

`com.phionalerter.ringdown`

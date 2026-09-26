import 'dart:io';

import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update.dart';
import 'api_client.dart';

class UpdateService {
  UpdateService(this._api);

  final ApiClient _api;

  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.phionalerter.ringdown';

  // The store_url that /app/version returns is launched externally with no
  // further confirmation, so a compromised or MITM'd response must not be
  // able to point the phone at an arbitrary URL (phishing, a non-store
  // scheme, etc). Only accept https links to a known app-store host.
  static const _allowedStoreHosts = {
    'play.google.com',
    'apps.apple.com',
    'testflight.apple.com',
  };

  static bool _isTrustedStoreUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return false;
    return _allowedStoreHosts.contains(uri.host);
  }

  Future<AppUpdateOffer?> check() async {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    final raw = await _api.appVersion();
    final key = Platform.isIOS ? 'ios' : 'android';
    final platform = raw[key];
    if (platform is! Map) return null;
    final latestBuild = _asInt(platform['build']);
    if (latestBuild <= 0 || latestBuild <= currentBuild) return null;
    final minBuild = _asInt(platform['min_build']);
    var storeUrl = (platform['store_url'] as String?)?.trim();
    if (storeUrl != null &&
        storeUrl.isNotEmpty &&
        !_isTrustedStoreUrl(storeUrl)) {
      storeUrl = null;
    }
    final message = (platform['message'] as String?)?.trim();
    return AppUpdateOffer(
      latestVersion: (platform['version'] as String?)?.trim().isNotEmpty == true
          ? platform['version'] as String
          : info.version,
      latestBuild: latestBuild,
      currentBuild: currentBuild,
      force: minBuild > 0 && currentBuild < minBuild,
      message: (message == null || message.isEmpty)
          ? (Platform.isIOS
              ? 'A new version is on TestFlight.'
              : 'A new version is available on the Play Store.')
          : message,
      storeUrl: (storeUrl == null || storeUrl.isEmpty)
          ? (Platform.isIOS ? null : _playStoreUrl)
          : storeUrl,
    );
  }

  Future<void> install(AppUpdateOffer offer) async {
    if (Platform.isAndroid) {
      try {
        final play = await InAppUpdate.checkForUpdate();
        if (play.updateAvailability == UpdateAvailability.updateAvailable) {
          await InAppUpdate.performImmediateUpdate();
          return;
        }
      } catch (_) {
        // Sideloaded installs and Play API failures fall through to the store.
      }
    }
    final raw = offer.storeUrl;
    if (raw == null || raw.isEmpty || !_isTrustedStoreUrl(raw)) return;
    final uri = Uri.parse(raw);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

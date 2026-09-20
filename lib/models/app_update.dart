class AppUpdateOffer {
  const AppUpdateOffer({
    required this.latestVersion,
    required this.latestBuild,
    required this.currentBuild,
    required this.force,
    required this.message,
    this.storeUrl,
  });

  final String latestVersion;
  final int latestBuild;
  final int currentBuild;
  final bool force;
  final String message;
  final String? storeUrl;
}

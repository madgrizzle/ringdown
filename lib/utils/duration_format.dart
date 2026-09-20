/// Compact live-timer format: `12s`, `3m 12s`, `1h 04m`, `2d 3h`.
String formatCompactDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays;
  final hours = d.inHours;
  final minutes = d.inMinutes;
  final seconds = d.inSeconds;
  if (days > 0) {
    return '${days}d ${hours.remainder(24)}h';
  }
  if (hours > 0) {
    final m = minutes.remainder(60).toString().padLeft(2, '0');
    return '${hours}h ${m}m';
  }
  if (minutes > 0) {
    final s = seconds.remainder(60).toString().padLeft(2, '0');
    return '${minutes}m ${s}s';
  }
  return '${seconds}s';
}

String formatDurationSpoken(Duration d, {required String prefix}) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final parts = <String>[];
  if (days > 0) parts.add('$days ${days == 1 ? 'day' : 'days'}');
  if (hours > 0) parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
  if (days == 0 && minutes > 0) {
    parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');
  }
  if (days == 0 && hours == 0 && minutes == 0) {
    parts.add('$seconds ${seconds == 1 ? 'second' : 'seconds'}');
  }
  return '$prefix ${parts.join(' ')}';
}

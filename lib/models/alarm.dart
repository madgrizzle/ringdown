class Alarm {
  const Alarm({
    required this.id,
    required this.siteId,
    required this.device,
    required this.description,
    required this.status,
    required this.state,
    required this.priority,
    required this.alarmAt,
    required this.receivedAt,
    this.clearedAt,
    required this.acked,
    this.aid,
    this.ackedBy,
    this.ackedAt,
    this.rawSubject,
    this.rawBody,
    this.recipientEmail,
    this.messageId,
    this.correlationKey,
  });

  final int id;
  final String siteId;
  final String device;
  final String description;

  /// Telenium letter: Y = in alarm, N = cleared.
  final String status;

  /// UI status: active | cleared.
  final String state;
  final int priority;
  final String? aid;
  final DateTime alarmAt;
  final DateTime receivedAt;

  /// When the gateway recorded the clear. Null while the alarm is still active.
  final DateTime? clearedAt;
  final bool acked;
  final String? ackedBy;
  final DateTime? ackedAt;
  final String? rawSubject;
  final String? rawBody;
  final String? recipientEmail;
  final String? messageId;

  /// The server's own dedup/grouping key for this alarm condition, when it
  /// sends one. Prefer this over reconstructing a key client-side.
  final String? correlationKey;

  /// `state` is always populated in [fromJson] (defaulted from `status` when
  /// the server omits it), so it alone is authoritative. Do not OR it with
  /// `status`: the two can legitimately disagree (e.g. a suppressed/
  /// maintenance-cleared row that Telenium hasn't re-polled to `N` yet), and
  /// `state` is the field the gateway means to be the source of truth.
  bool get isActive => state == 'active';
  bool get isCleared => !isActive;

  /// Server currently accepts ACK only on in-alarm (Y) rows.
  bool get canAck => !acked && status == 'Y';

  /// Latest receive, clear, or acknowledge time. Matches the server sync order.
  DateTime get changeTime {
    var latest = receivedAt;
    if (clearedAt != null && clearedAt!.isAfter(latest)) latest = clearedAt!;
    if (ackedAt != null && ackedAt!.isAfter(latest)) latest = ackedAt!;
    return latest;
  }

  factory Alarm.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] as String? ?? 'Y').toUpperCase();
    final state = (json['state'] as String?) ??
        (status == 'Y' ? 'active' : 'cleared');
    return Alarm(
      id: json['id'] as int,
      siteId: json['site_id'] as String? ?? '',
      device: json['device'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: status,
      state: state,
      priority: _parsePriority(json['priority']),
      aid: json['aid'] as String?,
      alarmAt: parseUtc(json['alarm_at']),
      receivedAt: parseUtc(json['received_at']),
      clearedAt: json['cleared_at'] == null ? null : parseUtc(json['cleared_at']),
      acked: json['acked'] as bool? ?? false,
      ackedBy: json['acked_by'] as String?,
      ackedAt: json['acked_at'] == null ? null : parseUtc(json['acked_at']),
      rawSubject: json['raw_subject'] as String?,
      rawBody: json['raw_body'] as String?,
      recipientEmail: json['recipient_email'] as String?,
      messageId: json['message_id'] as String?,
      correlationKey: json['correlation_key'] as String?,
    );
  }

  /// Tolerates a blank string (not just a missing/null value) so one bad row
  /// can't fail `int.parse`/cast and take down parsing of the whole page.
  static int _parsePriority(dynamic value) {
    if (value == null) return 20;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 20;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'site_id': siteId,
        'device': device,
        'description': description,
        'status': status,
        'state': state,
        'priority': priority,
        'aid': aid,
        'alarm_at': alarmAt.toIso8601String(),
        'received_at': receivedAt.toIso8601String(),
        'cleared_at': clearedAt?.toIso8601String(),
        'acked': acked,
        'acked_by': ackedBy,
        'acked_at': ackedAt?.toIso8601String(),
        'raw_subject': rawSubject,
        'raw_body': rawBody,
        'recipient_email': recipientEmail,
        'message_id': messageId,
        'correlation_key': correlationKey,
      };

  Alarm copyWith({
    bool? acked,
    String? ackedBy,
    DateTime? ackedAt,
    String? status,
    String? state,
  }) {
    return Alarm(
      id: id,
      siteId: siteId,
      device: device,
      description: description,
      status: status ?? this.status,
      state: state ?? this.state,
      priority: priority,
      aid: aid,
      alarmAt: alarmAt,
      receivedAt: receivedAt,
      clearedAt: clearedAt,
      acked: acked ?? this.acked,
      ackedBy: ackedBy ?? this.ackedBy,
      ackedAt: ackedAt ?? this.ackedAt,
      rawSubject: rawSubject,
      rawBody: rawBody,
      recipientEmail: recipientEmail,
      messageId: messageId,
      correlationKey: correlationKey,
    );
  }

  /// Treat API timestamps as UTC. Naive values are interpreted as UTC, not local.
  static DateTime parseUtc(dynamic value) {
    if (value is DateTime) {
      return value.isUtc
          ? value
          : DateTime.utc(
              value.year,
              value.month,
              value.day,
              value.hour,
              value.minute,
              value.second,
              value.millisecond,
              value.microsecond,
            );
    }
    final s = value as String;
    final dt = DateTime.parse(s);
    if (dt.isUtc) return dt;
    return DateTime.utc(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
  }
}

class AlarmListPage {
  const AlarmListPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    this.serverTime,
    this.hasMore = false,
    this.nextAfterTime,
    this.nextAfterId,
  });

  final List<Alarm> items;
  final int total;
  final int page;
  final int pageSize;
  final DateTime? serverTime;
  final bool hasMore;
  final DateTime? nextAfterTime;
  final int? nextAfterId;

  factory AlarmListPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return AlarmListPage(
      items: raw
          .map((e) => Alarm.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? raw.length,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? raw.length,
      serverTime: json['server_time'] == null
          ? null
          : Alarm.parseUtc(json['server_time']),
      hasMore: json['has_more'] as bool? ?? false,
      nextAfterTime: json['next_after_time'] == null
          ? null
          : Alarm.parseUtc(json['next_after_time']),
      nextAfterId: json['next_after_id'] as int?,
    );
  }
}

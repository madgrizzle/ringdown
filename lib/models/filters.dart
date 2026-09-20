enum SortMode {
  timeNewest,
  timeOldest,
  siteAsc,
  siteDesc,
  deviceAsc,
  deviceDesc,
  siteThenDevice,
  status,
  unackedFirst,
  longestActive,
  longestUnacked,
}

enum GroupBy { none, site, device }

extension SortModeX on SortMode {
  String get label => switch (this) {
        SortMode.timeNewest => 'Time (newest)',
        SortMode.timeOldest => 'Time (oldest)',
        SortMode.siteAsc => 'Site A–Z',
        SortMode.siteDesc => 'Site Z–A',
        SortMode.deviceAsc => 'Device A–Z',
        SortMode.deviceDesc => 'Device Z–A',
        SortMode.siteThenDevice => 'Site, then device',
        SortMode.status => 'Status',
        SortMode.unackedFirst => 'Unacked first',
        SortMode.longestActive => 'Longest active',
        SortMode.longestUnacked => 'Longest unacked',
      };

  bool get isClientSort => switch (this) {
        SortMode.siteThenDevice ||
        SortMode.status ||
        SortMode.unackedFirst ||
        SortMode.longestActive ||
        SortMode.longestUnacked =>
          true,
        _ => false,
      };

  /// API sort column when the server can do it.
  String get apiSort => switch (this) {
        SortMode.siteAsc || SortMode.siteDesc => 'site_id',
        SortMode.deviceAsc || SortMode.deviceDesc => 'device',
        _ => 'alarm_at',
      };

  String get apiOrder => switch (this) {
        SortMode.timeOldest || SortMode.siteAsc || SortMode.deviceAsc => 'asc',
        _ => 'desc',
      };
}

extension GroupByX on GroupBy {
  String get label => switch (this) {
        GroupBy.none => 'Flat list',
        GroupBy.site => 'By site',
        GroupBy.device => 'By device',
      };
}

class AlarmFilters {
  const AlarmFilters({
    this.hideCleared = true,
    this.unackedOnly = false,
    this.showHidden = false,
    this.siteContains = '',
    this.deviceContains = '',
    this.search = '',
    this.sort = SortMode.unackedFirst,
    this.groupBy = GroupBy.none,
  });

  final bool hideCleared;
  final bool unackedOnly;
  final bool showHidden;
  final String siteContains;
  final String deviceContains;
  final String search;
  final SortMode sort;
  final GroupBy groupBy;

  AlarmFilters copyWith({
    bool? hideCleared,
    bool? unackedOnly,
    bool? showHidden,
    String? siteContains,
    String? deviceContains,
    String? search,
    SortMode? sort,
    GroupBy? groupBy,
  }) {
    return AlarmFilters(
      hideCleared: hideCleared ?? this.hideCleared,
      unackedOnly: unackedOnly ?? this.unackedOnly,
      showHidden: showHidden ?? this.showHidden,
      siteContains: siteContains ?? this.siteContains,
      deviceContains: deviceContains ?? this.deviceContains,
      search: search ?? this.search,
      sort: sort ?? this.sort,
      groupBy: groupBy ?? this.groupBy,
    );
  }

  Map<String, dynamic> toJson() => {
        'hideCleared': hideCleared,
        'unackedOnly': unackedOnly,
        'showHidden': showHidden,
        'siteContains': siteContains,
        'deviceContains': deviceContains,
        'search': search,
        'sort': sort.name,
        'groupBy': groupBy.name,
      };

  factory AlarmFilters.fromJson(Map<String, dynamic> json) {
    return AlarmFilters(
      hideCleared: json['hideCleared'] as bool? ?? true,
      unackedOnly: json['unackedOnly'] as bool? ?? false,
      showHidden: json['showHidden'] as bool? ?? false,
      siteContains: json['siteContains'] as String? ?? '',
      deviceContains: json['deviceContains'] as String? ?? '',
      search: json['search'] as String? ?? '',
      sort: SortMode.values.firstWhere(
        (e) => e.name == json['sort'],
        orElse: () => SortMode.unackedFirst,
      ),
      groupBy: GroupBy.values.firstWhere(
        (e) => e.name == json['groupBy'],
        orElse: () => GroupBy.none,
      ),
    );
  }
}

import 'dart:convert';

/// 事件类型：版本更新 / 卡池轮换 / 活动
enum EventType { version, banner, event }

extension EventTypeX on EventType {
  String get label => switch (this) {
        EventType.version => '版本',
        EventType.banner => '卡池',
        EventType.event => '活动',
      };
}

/// 游戏定义
class Game {
  final String id;
  final String name;
  final String short; // 单字简称，用于头像
  final int primaryColor;
  final int secondaryColor;
  final String? miyousheForumId; // 米游社官方分区 id，非米系为 null
  final String? miyousheSlug; // 米游社网址 slug（ys/sr/zzz/bh3），用于拼文章链接
  final String? officialNewsUrl; // 官网资讯页（HTML 抓取用）
  final String? iconUrl; // 官方 APP 图标，null 时回退汉字块
  final String mascot; // 兜底看板 emoji
  final bool placeholder; // 预约中/占位游戏

  const Game({
    required this.id,
    required this.name,
    required this.short,
    required this.primaryColor,
    required this.secondaryColor,
    this.miyousheForumId,
    this.miyousheSlug,
    this.officialNewsUrl,
    this.iconUrl,
    required this.mascot,
    this.placeholder = false,
  });
}

/// 一条更新事件（版本更新 / 卡池轮换 / 活动）
class UpdateEvent {
  final String gameId;
  final EventType type;
  final String title;
  final String summary;
  final DateTime date; // 公告发布日期（兜底标记用）
  final DateTime? activityDate; // 活动/版本/卡池开始时间；非空时日历按此标记
  final String? url;
  final String? cover;

  const UpdateEvent({
    required this.gameId,
    required this.type,
    required this.title,
    required this.summary,
    required this.date,
    this.activityDate,
    this.url,
    this.cover,
  });

  /// 日历与当日列表实际使用的日期：优先活动开始时间
  DateTime get effectiveDate => activityDate ?? date;

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'type': type.index,
        'title': title,
        'summary': summary,
        'date': date.millisecondsSinceEpoch,
        'activityDate': activityDate?.millisecondsSinceEpoch,
        'url': url,
        'cover': cover,
      };

  factory UpdateEvent.fromJson(Map<String, dynamic> j) => UpdateEvent(
        gameId: j['gameId'] as String,
        type: EventType.values[j['type'] as int],
        title: j['title'] as String,
        summary: j['summary'] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(j['date'] as int),
        activityDate: j['activityDate'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['activityDate'] as int),
        url: j['url'] as String?,
        cover: j['cover'] as String?,
      );

  static String encodeList(List<UpdateEvent> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<UpdateEvent> decodeList(String s) {
    final raw = jsonDecode(s) as List;
    return raw
        .map((e) => UpdateEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

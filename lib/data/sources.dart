import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../models.dart';

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 15),
  headers: {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36',
  },
));

/// 数据源接口：每个游戏一个来源，统一输出标准事件
abstract class GameSource {
  Future<List<UpdateEvent>> fetch(Game game);
}

/// 关键词分类
EventType classify(String text) {
  final t = text.toLowerCase();
  if (RegExp(r'卡池|祈愿|跃迁|调频|共鸣|up|招募|抽卡|限定').hasMatch(t)) {
    return EventType.banner;
  }
  if (RegExp(r'版本更新|维护|更新公告|预下载|停服|开服|版本预告|版本').hasMatch(t)) {
    return EventType.version;
  }
  return EventType.event;
}

/// 从文本中推断事件日期：优先 "M月D日"，其次 "MM-DD"，失败返回 null
DateTime? extractDate(String text) {
  final m = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*日').firstMatch(text);
  if (m != null) {
    return _resolveDate(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }
  // 形如 "07-29 《阴阳师》..." 的日期前缀
  final m2 = RegExp(r'(\d{1,2})-(\d{1,2})\s').firstMatch(text);
  if (m2 != null) {
    final month = int.parse(m2.group(1)!);
    final day = int.parse(m2.group(2)!);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return _resolveDate(month, day);
    }
  }
  return null;
}

DateTime _resolveDate(int month, int day) {
  final now = DateTime.now();
  var year = now.year;
  if (month > now.month + 2) year -= 1;
  return DateTime(year, month, day);
}

/// 从 HTML 内容里提取第一张图片
String? firstImg(String html) {
  final m = RegExp(r'''<img[^>]+src=["']([^"']+)''').firstMatch(html);
  return m?.group(1);
}

/// 米游社官方分区帖子（实测可用 2026-07）
/// GET https://bbs-api.miyoushe.com/post/wapi/getForumPostList?forum_id={id}&is_hot=false&page_size=30&sort_type=1
class MiyousheSource implements GameSource {
  @override
  Future<List<UpdateEvent>> fetch(Game game) async {
    final forumId = game.miyousheForumId;
    if (forumId == null) return [];
    final resp = await _dio.get(
      'https://bbs-api.miyoushe.com/post/wapi/getForumPostList',
      queryParameters: {
        'forum_id': forumId,
        'is_hot': 'false',
        'page_size': '30',
        'sort_type': '1',
      },
    );
    final data = resp.data;
    if (data is! Map || data['retcode'] != 0) return [];
    final list = (data['data']?['list'] as List?) ?? [];
    final events = <UpdateEvent>[];
    for (final item in list) {
      final post = item['post'];
      if (post == null) continue;
      final subject = (post['subject'] as String? ?? '').trim();
      if (subject.isEmpty) continue;
      final content = (post['content'] as String? ?? '');
      final plain =
          content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      final summary = plain.length > 80 ? '${plain.substring(0, 80)}…' : plain;
      final created = post['created_at'];
      final postDate = created is int
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : DateTime.now();
      final images = (post['images'] as List?)?.cast<String>() ?? const [];
      final cover = images.isNotEmpty ? images.first : firstImg(content);
      final slug = game.miyousheSlug ?? 'ys';
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify('$subject $plain'),
        title: subject,
        summary: summary,
        date: extractDate('$subject $plain') ?? postDate,
        url: 'https://www.miyoushe.com/$slug/article/${post['post_id']}',
        cover: cover,
      ));
    }
    return events;
  }
}

/// 官网 HTML 抓取（易碎，失败返回空，由仓库层回退）
class OfficialWebSource implements GameSource {
  @override
  Future<List<UpdateEvent>> fetch(Game game) async {
    final url = game.officialNewsUrl;
    if (url == null) return [];
    final resp = await _dio.get(url);
    final doc = html_parser.parse(resp.data.toString());
    final events = <UpdateEvent>[];
    // 通用策略：抓所有包含资讯链接特征的 <a>，取其文本
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      final title = a.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (title.length < 8) continue;
      if (!RegExp(r'news|detail|article|notice|id=\d+|/\d+\.html').hasMatch(href)) {
        continue;
      }
      final fullUrl = href.startsWith('http')
          ? href
          : Uri.parse(url).resolve(href).toString();
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify(title),
        title: title,
        summary: '',
        date: extractDate(title) ?? DateTime.now(),
        url: fullUrl,
      ));
      if (events.length >= 20) break;
    }
    // 按标题去重
    final seen = <String>{};
    return events.where((e) => seen.add(e.title)).toList();
  }
}

/// 明日方舟专用：官网 /news 页 SSR 内嵌 JSON
/// 新闻列表项：{"cid":"9683","title":"...","displayTime":..,"brief":"..."}
/// 轮播项：{"title":"...","pcCover":"...","link":".../news/8571","ts":..}
class ArknightsSource implements GameSource {
  static final _itemRe = RegExp(
    r'\\"cid\\":\\"(?<cid>\d+)\\"'
    r'.*?\\"title\\":\\"(?<title>[^"]+)\\"'
    r'.*?\\"displayTime\\":(?<ts>\d+)'
    r'.*?\\"brief\\":\\"(?<brief>[^"]*)\\"',
    dotAll: true,
  );
  static final _coverRe = RegExp(
    r'\\"title\\":\\"(?<title>[^"]+)\\"'
    r'.*?\\"pcCover\\":\\"(?<cover>[^"]+)\\"'
    r'.*?\\"link\\":\\"(?<link>[^"]+)\\"'
    r'.*?\\"ts\\":(?<ts>\d+)',
    dotAll: true,
  );

  @override
  Future<List<UpdateEvent>> fetch(Game game) async {
    final resp = await _dio.get('https://ak.hypergryph.com/news');
    final body = resp.data.toString();
    final events = <UpdateEvent>[];
    final seen = <String>{};
    // 先抓轮播项（带封面图，通常是最新活动/版本宣传图）
    final coverMap = <String, String>{};
    for (final m in _coverRe.allMatches(body)) {
      final title = m.namedGroup('title')!.trim();
      final cover = m.namedGroup('cover')!;
      if (cover.isNotEmpty) coverMap[title] = cover;
    }
    for (final m in _itemRe.allMatches(body)) {
      final title = m.namedGroup('title')!.trim();
      if (title.length < 4 || !seen.add(title)) continue;
      final cid = m.namedGroup('cid')!;
      final ts = int.tryParse(m.namedGroup('ts')!) ?? 0;
      final brief = m.namedGroup('brief')!.trim();
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify('$title $brief'),
        title: title,
        summary: brief.length > 80 ? '${brief.substring(0, 80)}…' : brief,
        date: ts > 0
            ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
            : (extractDate(title) ?? DateTime.now()),
        url: 'https://ak.hypergryph.com/news/$cid',
        cover: coverMap[title],
      ));
      if (events.length >= 30) break;
    }
    return events;
  }
}

/// 库洛官网 CDN 静态 JSON（鸣潮/战双同源基建）
/// 字段：articleId / articleTitle / articleType / createTime / startTime / articleCover / articleContent
class KuroCmsSource implements GameSource {
  final String listUrl;
  final String detailBase; // 详情页基础地址，{id} 会被替换

  KuroCmsSource({required this.listUrl, required this.detailBase});

  static final _dateRe = RegExp(r'(\d{4})-(\d{2})-(\d{2})');

  @override
  Future<List<UpdateEvent>> fetch(Game game) async {
    final resp = await _dio.get(listUrl);
    final data = resp.data;
    if (data is! List) return [];
    final events = <UpdateEvent>[];
    final seen = <String>{};
    for (final item in data) {
      if (item is! Map) continue;
      final title = (item['articleTitle'] as String? ?? '').trim();
      if (title.length < 4 || !seen.add(title)) continue;
      final id = item['articleId'];
      final startTime = item['startTime'] as String? ?? '';
      final m = _dateRe.firstMatch(startTime);
      final date = m != null
          ? DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
              int.parse(m.group(3)!))
          : (extractDate(title) ?? DateTime.now());
      final rawContent = item['articleContent'] as String? ?? '';
      final content = rawContent
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final cover = (item['articleCover'] as String?) ?? '';
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify('$title $content'),
        title: title,
        summary: content.length > 80 ? '${content.substring(0, 80)}…' : content,
        date: date,
        url: id != null
            ? detailBase.replaceAll('{id}', id.toString())
            : null,
        cover: cover.isNotEmpty ? cover : firstImg(rawContent),
      ));
      if (events.length >= 30) break;
    }
    return events;
  }
}

/// 异环专用：官网 /m/news/ 服务端渲染列表
/// 结构：<a href="/m/news/xxx/20260722/263235.html"><h2 class="title">..</h2><div class="des">..</div><p class="date">2026-07-22</p>
class YihuanSource implements GameSource {
  static const _base = 'https://yh.wanmei.com';

  @override
  Future<List<UpdateEvent>> fetch(Game game) async {
    final resp = await _dio.get('$_base/m/news/');
    final doc = html_parser.parse(resp.data.toString());
    final events = <UpdateEvent>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (!RegExp(r'/m/news/[a-z]+/\d{8}/\d+\.html').hasMatch(href)) continue;
      final titleEl = a.querySelector('h2.title') ?? a.querySelector('.title');
      final title = (titleEl?.text ?? a.text).trim().replaceAll(RegExp(r'\s+'), ' ');
      if (title.length < 4 || !seen.add(title)) continue;
      final des = a.querySelector('.des')?.text.trim() ?? '';
      final dateStr = a.querySelector('.date')?.text.trim() ?? '';
      final dm = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(dateStr);
      final img = a.querySelector('img')?.attributes['src'];
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify('$title $des'),
        title: title,
        summary: des.length > 80 ? '${des.substring(0, 80)}…' : des,
        date: dm != null
            ? DateTime(int.parse(dm.group(1)!), int.parse(dm.group(2)!),
                int.parse(dm.group(3)!))
            : (extractDate('$title $des') ?? DateTime.now()),
        url: href.startsWith('http') ? href : '$_base$href',
        cover: img,
      ));
      if (events.length >= 30) break;
    }
    return events;
  }
}

/// Gamekee Wiki 资讯接口（用于 Nikke 国服等官网难抓的游戏）
/// GET https://www.gamekee.com/v1/content/list?type=2&page=1&limit=20
/// 需 header game-alias；type=2 为官方资讯/公告
class GamekeeSource implements GameSource {
  final String alias; // game-alias，如 nikke
  final String detailBase; // 详情页基础地址，{id} 替换

  GamekeeSource({required this.alias, required this.detailBase});

  @override
  Future<List<UpdateEvent>> fetch(Game game) async {
    final resp = await _dio.get(
      'https://www.gamekee.com/v1/content/list',
      queryParameters: {'type': '2', 'page': '1', 'limit': '20'},
      options: Options(headers: {
        'game-alias': alias,
        'Referer': 'https://www.gamekee.com/$alias/',
      }),
    );
    final data = resp.data;
    if (data is! Map || data['code'] != 0) return [];
    final list = (data['data'] as List?) ?? [];
    final events = <UpdateEvent>[];
    for (final item in list) {
      if (item is! Map) continue;
      final title = (item['title'] as String? ?? '').trim();
      if (title.length < 4) continue;
      final id = item['id'];
      final created = item['created_at'];
      final date = created is int
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : (extractDate(title) ?? DateTime.now());
      final summary = (item['summary'] as String? ?? '')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify('$title $summary'),
        title: title,
        summary: summary.length > 80 ? '${summary.substring(0, 80)}…' : summary,
        date: date,
        url: id != null ? detailBase.replaceAll('{id}', id.toString()) : null,
      ));
      if (events.length >= 20) break;
    }
    return events;
  }
}

/// 兜底数据：网络/解析全失败时保证 UI 有内容
class MockSource implements GameSource {
  static final _now = DateTime.now();

  @override
  Future<List<UpdateEvent>> fetch(Game game) async {
    if (game.placeholder) {
      return [
        UpdateEvent(
          gameId: game.id,
          type: EventType.event,
          title: '${game.name} · 预约进行中',
          summary: '游戏尚未上线，官方动态将在上线后自动接入',
          date: _now,
        ),
      ];
    }
    return [
      UpdateEvent(
        gameId: game.id,
        type: EventType.event,
        title: '${game.name} · 数据源校准中',
        summary: '该游戏官网为动态渲染页面，解析规则适配中，敬请期待',
        date: _now,
      ),
    ];
  }
}

/// 为游戏选择合适的数据源
GameSource sourceFor(Game game) {
  switch (game.id) {
    case 'arknights':
      return ArknightsSource();
    case 'wuwa':
      return KuroCmsSource(
        listUrl:
            'https://media-cdn-mingchao.kurogame.com/akiwebsite/website2.0/json/G152/zh/ArticleMenu.json',
        detailBase: 'https://mc.kurogames.com/main/news/detail/{id}',
      );
    case 'pgr':
      return KuroCmsSource(
        listUrl:
            'https://media-cdn-zspms.kurogame.com/pnswebsite/website2.0/json/G144/ArticleMenu.json',
        detailBase: 'https://pns.kurogames.com/news/{id}',
      );
    case 'yihuan':
      return YihuanSource();
    case 'nikke':
      return GamekeeSource(
        alias: 'nikke',
        detailBase: 'https://www.gamekee.com/nikke/{id}',
      );
  }
  if (game.miyousheForumId != null) return MiyousheSource();
  if (game.officialNewsUrl != null) return OfficialWebSource();
  return MockSource();
}

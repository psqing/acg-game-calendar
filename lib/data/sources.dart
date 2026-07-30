import 'package:dio/dio.dart';
import 'package:html/dom.dart';
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

/// 候选日期（带打分，用于挑「活动开始时间」）
class _DateCandidate {
  final DateTime date;
  final int score;
  _DateCandidate(this.date, this.score);
}

/// 把 M月D日 / M-D / M/D 这类「无年份」日期，按参考日期（发布日）推断年份：
/// 若候选日早于发布日，但差距不超过 45 天（即「晚发公告」），仍视为今年；
/// 否则（明显属于上一年度）视为次年。
DateTime _resolveActivityDate(int month, int day, DateTime ref) {
  var year = ref.year;
  final candidate = DateTime(year, month, day);
  if (candidate.isBefore(ref) && ref.difference(candidate).inDays > 45) {
    year += 1;
  }
  return DateTime(year, month, day);
}

/// 活动开始时间抽取用的正则（模块级，避免重复编译）
final _activityLabelRe = RegExp(
  r'(?:活动(?:开启)?时间|开放时间|开启时间)\s*[:：]?\s*(\d{4})[-年/](\d{1,2})[-月](\d{1,2})日?'
  r'|(?:活动(?:开启)?时间|开放时间|开启时间)\s*[:：]?\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?',
);
/// 时间段：「DATE1 分隔符 DATE2」区间，取起始日 DATE1。
/// 例如「7月22日维护后-8月11日23:59」「2026-08-01 至 2026-08-15」。
final _activityRangeRe = RegExp(
  r'(?:(\d{4})[-年/](\d{1,2})[-月](\d{1,2})日?|(\d{1,2})\s*月\s*(\d{1,2})\s*日?)'
  r'[\s\S]{0,16}?'
  r'(?:[-~–—至到])'
  r'[\s\S]{0,16}?'
  r'(?:\d{4}[-年/]\d{1,2}[-月]\d{1,2}日?|\d{1,2}\s*月\s*\d{1,2}\s*日?)',
);
/// 模糊起始：区间起始是「版本更新后 / 维护后」等且无明确日期，如「1.2版本更新后~2026年…」
final _activityVagueRe = RegExp(
  r'(版本更新后|更新后|维护后|开服后|上线后|版本更新)\s*[-~–—至到]',
);
/// 通用日期 token（YYYY-MM-DD / YYYY年M月D日 / M月D日）
final _dateTokenRe = RegExp(
  r'(\d{4})[-年/](\d{1,2})[-月](\d{1,2})日?|(\d{1,2})\s*月\s*(\d{1,2})\s*日?',
);

/// 把 _dateTokenRe 的匹配解析为 DateTime
/// （group1-3 = YYYY-MM-DD，group4-5 = M月D日）
DateTime _parseDateToken(RegExpMatch m, DateTime publish) {
  if (m.group(1) != null) {
    return DateTime(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
  return _resolveActivityDate(
      int.parse(m.group(4)!), int.parse(m.group(5)!), publish);
}

/// 从公告文本中提取「活动/版本/卡池的开始时间」，供日历按活动日标记。
/// 找不到可靠活动日时返回 null（调用方回退到发布日）。
///
/// 策略：
/// 1. 高置信度：先匹配「活动时间 / 开放时间 / 开启时间：M月D日」直接作为开始日；
/// 2. 时间段：识别「DATE1 分隔符 DATE2」区间（如「7月22日维护后-8月11日」），取起始日 DATE1
///    —— 避免被结束日（如 8月11日）覆盖；
/// 3. 模糊起始：若区间起始是「版本更新后 / 维护后」等且前面无任何明确日期
///    （如「1.2版本更新后~2026年…」），视为起始日不明确，返回 null（落到发布日）；
/// 4. 通用兜底：收集正文所有日期，按上下文打分取发布日之后、180 天内最像“开始”的日期。
DateTime? extractActivityDate(String text, DateTime publish) {
  if (text.isEmpty) return null;

  // 1) 高置信度：活动时间 / 开放时间 / 开启时间（直接给出开始日）
  final lm = _activityLabelRe.firstMatch(text);
  if (lm != null) {
    final d = _parseDateToken(lm, publish);
    if (d.isAtSameMomentAs(publish) || d.isAfter(publish)) return d;
  }

  // 2) 时间段：取起始日 DATE1（覆盖「7月22日维护后-8月11日」这类）
  final rm = _activityRangeRe.firstMatch(text);
  if (rm != null) {
    return _parseDateToken(rm, publish);
  }

  // 3) 模糊起始：起始时间无明确日期（如「1.2版本更新后~2026年…」）→ 用发布日
  final vm = _activityVagueRe.firstMatch(text);
  if (vm != null && !_dateTokenRe.hasMatch(text.substring(0, vm.start))) {
    return null;
  }

  // 4) 通用候选收集 + 打分
  final candidates = <_DateCandidate>[];
  for (final m in _dateTokenRe.allMatches(text)) {
    final dt = _parseDateToken(m, publish);
    var score = 0;
    final end = m.end;
    final winEnd = end + 20 > text.length ? text.length : end + 20;
    final window = text.substring(end, winEnd);
    if (RegExp(r'活动开启|开启|开放|上线|开服|版本更新|版本|复刻|新版本|卡池|祈愿|跃迁|调频|共鸣|前瞻').hasMatch(window)) {
      score += 2;
    }
    if (RegExp(r'维护|停服|闪断|例行').hasMatch(window)) score -= 1;
    final beforeStart = end - 14 < 0 ? 0 : end - 14;
    final before = text.substring(beforeStart, end);
    if (RegExp(r'活动时间|开放时间|开启时间').hasMatch(before)) score += 1;
    candidates.add(_DateCandidate(dt, score));
  }
  final future = candidates
      .where((c) =>
          c.date.isAfter(publish) &&
          c.date.difference(publish).inDays <= 180)
      .toList();
  if (future.isEmpty) return null;
  future.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    return a.date.compareTo(b.date);
  });
  return future.first.date;
}

/// 从 HTML 内容里提取第一张图片
String? firstImg(String html) {
  final m = RegExp(r'''<img[^>]+src=["']([^"']+)''').firstMatch(html);
  return m?.group(1);
}

/// 清洗文本：去 HTML 标签、解码实体、还原被二次转义的换行(//n //t //r 等)、折叠空白。
/// 用于库洛/方舟等正文中残留的「前端标签 + 乱码 + 转义换行」。
String cleanText(String raw) {
  if (raw.isEmpty) return raw;
  var s = html_parser.parse(raw).body?.text ?? raw;
  // 方舟 SSR 中的 //n 等二次转义换行
  s = s.replaceAll('//n', ' ').replaceAll('//r', ' ').replaceAll('//t', ' ');
  // 常规反斜杠转义（兜底）
  s = s.replaceAll('\\n', ' ').replaceAll('\\t', ' ').replaceAll('\\r', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// 从已解析的 HTML 文档提取第一张「内容图」（优先含 resources/ 的 banner 图）
String? firstImgFromHtml(Document doc) {
  String? fallback;
  for (final img in doc.querySelectorAll('img')) {
    final src = img.attributes['src']?.trim();
    if (src == null || src.isEmpty || src.startsWith('data:')) continue;
    if (src.contains('resources/')) return src;
    fallback ??= src;
  }
  return fallback;
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
      final plain = cleanText(content);
      final summary = plain.length > 80 ? '${plain.substring(0, 80)}…' : plain;
      final activityText = '$subject $plain';
      final created = post['created_at'];
      final postDate = created is int
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : DateTime.now();
      final images = (post['images'] as List?)?.cast<String>() ?? const [];
      final cover = images.isNotEmpty ? images.first : firstImg(content);
      final slug = game.miyousheSlug ?? 'ys';
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify(activityText),
        title: cleanText(subject),
        summary: summary,
        date: extractDate(activityText) ?? postDate,
        activityDate: extractActivityDate(activityText, postDate),
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
      final publish = extractDate(title) ?? DateTime.now();
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify(title),
        title: cleanText(title),
        summary: '',
        date: publish,
        activityDate: extractActivityDate(title, publish),
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
      final title = cleanText(m.namedGroup('title')!);
      if (title.length < 4 || !seen.add(title)) continue;
      final cid = m.namedGroup('cid')!;
      final ts = int.tryParse(m.namedGroup('ts')!) ?? 0;
      final brief = cleanText(m.namedGroup('brief')!);
      final publish = ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
          : (extractDate(title) ?? DateTime.now());
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify('$title $brief'),
        title: title,
        summary: brief.length > 80 ? '${brief.substring(0, 80)}…' : brief,
        date: publish,
        activityDate: extractActivityDate('$title $brief', publish),
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
      final title = cleanText(item['articleTitle'] as String? ?? '');
      if (title.length < 4 || !seen.add(title)) continue;
      final id = item['articleId'];
      final startTime = item['startTime'] as String? ?? '';
      final m = _dateRe.firstMatch(startTime);
      final date = m != null
          ? DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
              int.parse(m.group(3)!))
          : (extractDate(title) ?? DateTime.now());
      final rawContent = item['articleContent'] as String? ?? '';
      final content = cleanText(rawContent);
      final rawCover =
          (item['articleCover'] as String?) ?? (item['suggestCover'] as String?) ?? '';
      final cover = rawCover.isNotEmpty
          ? rawCover
          : firstImgFromHtml(html_parser.parse(rawContent));
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify('$title $content'),
        title: title,
        summary: content.length > 80 ? '${content.substring(0, 80)}…' : content,
        date: date,
        activityDate: extractActivityDate('$title $content', date),
        url: id != null
            ? detailBase.replaceAll('{id}', id.toString())
            : null,
        cover: cover,
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
    final items = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (!RegExp(r'/m/news/[a-z]+/\d{8}/\d+\.html').hasMatch(href)) continue;
      final titleEl = a.querySelector('h2.title') ?? a.querySelector('.title');
      final title = cleanText(titleEl?.text ?? a.text);
      if (title.length < 4 || !seen.add(title)) continue;
      final des = cleanText(a.querySelector('.des')?.text.trim() ?? '');
      final dateStr = a.querySelector('.date')?.text.trim() ?? '';
      final dm = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(dateStr);
      final url = href.startsWith('http') ? href : '$_base$href';
      items.add({
        'title': title,
        'des': des,
        'date': dm != null
            ? DateTime(int.parse(dm.group(1)!), int.parse(dm.group(2)!),
                int.parse(dm.group(3)!))
            : (extractDate('$title $des') ?? DateTime.now()),
        'url': url,
        'cover': null,
      });
      if (items.length >= 30) break;
    }
    // 列表页不含头图，抓取前几条详情页提取 banner 作为封面 + 活动开始时间
    final top = items.take(6).toList();
    await Future.wait(top.map((item) async {
      try {
        final d = await _dio.get(item['url'] as String);
        final ddoc = html_parser.parse(d.data.toString());
        item['cover'] = firstImgFromHtml(ddoc);
        final dtext = ddoc.body?.text ?? '';
        item['activityDate'] =
            extractActivityDate('${item['title']} $dtext', item['date'] as DateTime);
      } catch (_) {
        item['cover'] = null;
      }
    }));
    return items.map((item) {
      final des = item['des'] as String;
      final title = item['title'] as String;
      final publish = item['date'] as DateTime;
      return UpdateEvent(
        gameId: game.id,
        type: classify('$title $des'),
        title: title,
        summary: des.length > 80 ? '${des.substring(0, 80)}…' : des,
        date: publish,
        activityDate: (item['activityDate'] as DateTime?) ??
            extractActivityDate('$title $des', publish),
        url: item['url'] as String,
        cover: item['cover'] as String?,
      );
    }).toList();
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
      final title = cleanText(item['title'] as String? ?? '');
      if (title.length < 4) continue;
      final id = item['id'];
      final created = item['created_at'];
      final date = created is int
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : (extractDate(title) ?? DateTime.now());
      final summary = cleanText(item['summary'] as String? ?? '');
      events.add(UpdateEvent(
        gameId: game.id,
        type: classify('$title $summary'),
        title: title,
        summary: summary.length > 80 ? '${summary.substring(0, 80)}…' : summary,
        date: date,
        activityDate: extractActivityDate('$title $summary', date),
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
        detailBase: 'https://www.gamekee.com/nikke/{id}.html',
      );
  }
  if (game.miyousheForumId != null) return MiyousheSource();
  if (game.officialNewsUrl != null) return OfficialWebSource();
  return MockSource();
}

import '../models.dart';

/// 游戏注册表：新增游戏 = 在这里加一行 + （可选）数据源配置
class GameRegistry {
  static const List<Game> games = [
    Game(
      id: 'genshin',
      name: '原神',
      short: '原',
      primaryColor: 0xFF4A90D9,
      secondaryColor: 0xFF7EC8F0,
      miyousheForumId: '28',
      miyousheSlug: 'ys',
      iconUrl: 'https://upload-bbs.mihoyo.com/game/ys/icon.png',
      mascot: '🌟',
    ),
    Game(
      id: 'hsr',
      name: '崩坏：星穹铁道',
      short: '铁',
      primaryColor: 0xFF7B5EA7,
      secondaryColor: 0xFFB99BE8,
      miyousheForumId: '53',
      miyousheSlug: 'sr',
      iconUrl:
          'https://fastcdn.mihoyo.com/static-resource-v2/2025/09/09/6d67420c3de1b8308a3691471075b91e_8846301207260982621.png',
      mascot: '🚂',
    ),
    Game(
      id: 'zzz',
      name: '绝区零',
      short: '绝',
      primaryColor: 0xFFD8A72A,
      secondaryColor: 0xFFF0D060,
      miyousheForumId: '58',
      miyousheSlug: 'zzz',
      iconUrl:
          'https://fastcdn.mihoyo.com/static-resource-v2/2026/07/21/f50b6661df7bc5038e5fb76e94e43182_6312065024033273127.png',
      mascot: '📺',
    ),
    Game(
      id: 'bh3',
      name: '崩坏3',
      short: '崩',
      primaryColor: 0xFF3AA8D8,
      secondaryColor: 0xFF8AE0F8,
      miyousheForumId: '6',
      miyousheSlug: 'bh3',
      iconUrl: 'https://upload-bbs.mihoyo.com/game/bh3/app_icon.png',
      mascot: '⚡',
    ),
    Game(
      id: 'arknights',
      name: '明日方舟',
      short: '舟',
      primaryColor: 0xFFE8762C,
      secondaryColor: 0xFFF8B060,
      officialNewsUrl: 'https://ak.hypergryph.com/news',
      // 官方品牌图（web.hycdn.cn，PNG 可直接解码）
      iconUrl:
          'https://web.hycdn.cn/arknights/official/_next/static/media/amiya.a410de75.png',
      mascot: '🛡️',
    ),
    Game(
      id: 'wuwa',
      name: '鸣潮',
      short: '鸣',
      primaryColor: 0xFF1FA69A,
      secondaryColor: 0xFF6AD8C8,
      // 官网只有 .ico（Flutter 无法解码），改用 TapTap 应用图标
      iconUrl:
          'https://img.tapimg.com/market/images/98aafaa86349a5fee8beea6928b7f140.png',
      // 数据源：库洛官网 CDN JSON（见 sources.dart KuroCmsSource）
      mascot: '🌊',
    ),
    Game(
      id: 'pgr',
      name: '战双帕弥什',
      short: '双',
      primaryColor: 0xFFB03A4A,
      secondaryColor: 0xFFE87888,
      iconUrl:
          'https://pns-cdnstatic.kurogames.com/resource/pns_website2.0/favicon.png',
      mascot: '⚙️',
    ),
    Game(
      id: 'nikke',
      name: '胜利女神：新的希望',
      short: '妮',
      primaryColor: 0xFFE85A8A,
      secondaryColor: 0xFFF8A0C0,
      iconUrl:
          'https://game.gtimg.cn/images/nikke/act/welfare202505/AppIcon_NK_221008.jpg',
      // 官网为腾讯 milo 网关动态加载，校准中 → MockSource 占位
      mascot: '🎀',
    ),
    Game(
      id: 'yys',
      name: '阴阳师',
      short: '阴',
      primaryColor: 0xFFC0392B,
      secondaryColor: 0xFFE8A048,
      officialNewsUrl: 'https://yys.163.com/news/',
      iconUrl: 'https://webinput.nie.netease.com/img/yys/icon.png/128',
      mascot: '🏮',
    ),
    Game(
      id: 'yihuan',
      name: '异环',
      short: '异',
      primaryColor: 0xFF6A5ACD,
      secondaryColor: 0xFFA898F0,
      officialNewsUrl: 'https://yh.wanmei.com/m/news/',
      iconUrl: 'https://yh.wanmei.com/m/images/cover240718/NTE_logo.png',
      mascot: '🌆',
    ),
  ];

  static Game byId(String id) => games.firstWhere(
        (g) => g.id == id,
        orElse: () => games.first,
      );
}

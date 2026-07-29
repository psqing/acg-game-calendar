# 二游日历 APP — 项目总览

## 已确认需求
- Flutter / Android，单人使用，数据 APP 内实时抓取（无后端）
- 游戏：米哈游系（原神/崩铁/绝区零/崩3）、明日方舟、鸣潮、战双、Nikke国服、阴阳师、异环（占位），支持勾选筛选
- 首屏 = 日历 + 当日更新列表；详情页 = 各游戏沉浸式主题（公告/卡池/活动 Tab）
- 缓存：公告 6h TTL，下拉强刷，失败回退缓存 → 兜底数据
- 主题：**日间 = 明亮幻想系（A），夜间 = 深色科幻系（B），一键切换**

## 工程结构
```
lib/
├─ main.dart              # 入口：Hive 初始化 + ProviderScope
├─ models.dart            # Game / UpdateEvent / EventType
├─ theme.dart             # 日间 A 主题 + 夜间 B 主题
├─ providers.dart         # Riverpod：主题/筛选/事件/选中日期
├─ data/
│  ├─ games.dart          # 游戏注册表（10 款，含配色/forumId/官网）
│  ├─ sources.dart        # MiyousheSource（实测可用）/ OfficialWebSource / MockSource
│  └─ repository.dart     # 缓存 + 聚合 + 回退
└─ ui/
   ├─ home_page.dart      # MainShell：日历 / 游戏 / 设置 三 Tab
   ├─ detail_page.dart    # 沉浸式详情页（SliverAppBar + 3 Tab）
   ├─ settings_page.dart  # 游戏勾选 + 清缓存
   └─ widgets.dart        # GameAvatar / EventCard / EventTypeTag
```

## 数据源实测（2026-07-29）
- ✅ 米游社官方分区帖子：`bbs-api.miyoushe.com/post/wapi/getForumPostList`（原神28/崩铁53/绝区零58/崩3-6）
- ⚠️ 方舟/鸣潮/战双/Nikke/阴阳师：官网 HTML 通用抓取（易碎，失败自动回退）
- ❌ 老 getNewsList 接口已下线

## 待办 / 后续
- 官网抓取源需要在真机上逐一校准（选择器策略较粗糙）
- 卡池"当期 UP 角色立绘"目前用卡池帖封面图代替，精确提取待后续迭代
- 异环上线后接入真实数据源

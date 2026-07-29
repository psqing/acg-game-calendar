import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../data/games.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'detail_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// 主框架：底部导航 = 日历 / 游戏 / 设置
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final night = ref.watch(nightModeProvider);
    final views = [
      const CalendarView(),
      const GamesView(),
      const SettingsView(),
    ];
    return Container(
      decoration: BoxDecoration(gradient: night ? nightGradient : dayGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: IndexedStack(index: _tab, children: views),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.calendar_month), label: '日历'),
            NavigationDestination(icon: Icon(Icons.sports_esports), label: '游戏'),
            NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      ),
    );
  }
}

/// 日历页
class CalendarView extends ConsumerWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    final selected = ref.watch(selectedDayProvider);
    final byDay = ref.watch(eventsByDayProvider);
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(refreshTriggerProvider.notifier).state++;
        await ref.read(eventsProvider.future);
        if (context.mounted) {
          final st = ref.read(fetchStatusProvider);
          final ok = st.values.where((v) => v.startsWith('ok')).length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ok == st.length && st.isNotEmpty
                  ? '刷新完成，$ok 个数据源全部正常'
                  : '刷新完成：$ok 个正常，${st.length - ok} 个异常（设置页可查看原因）'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // 头部
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${now.month}月${now.day}日 · 星期${'一二三四五六日'[now.weekday - 1]}',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 2,
                          color: night ? const Color(0xFF8A93A5) : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        night ? '二游日历_' : '二游日历',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: night ? 4 : 2,
                          color: night ? const Color(0xFFEEF2F8) : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // 日夜切换
                IconButton(
                  tooltip: night ? '切换日间模式' : '切换夜间模式',
                  icon: Icon(
                    night ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                    color: night ? const Color(0xFFF5C518) : Colors.white,
                  ),
                  onPressed: () =>
                      ref.read(nightModeProvider.notifier).toggle(),
                ),
              ],
            ),
          ),

          // 日历卡片
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TableCalendar<UpdateEvent>(
                locale: 'zh_CN',
                firstDay: DateTime(now.year - 1),
                lastDay: DateTime(now.year + 1),
                focusedDay: selected,
                selectedDayPredicate: (d) => isSameDay(d, selected),
                onDaySelected: (sel, foc) =>
                    ref.read(selectedDayProvider.notifier).state = sel,
                eventLoader: (day) {
                  final map = byDay.valueOrNull ?? {};
                  return map[DateTime(day.year, day.month, day.day)] ?? [];
                },
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: night
                        ? const Color(0xFFEEF2F8)
                        : const Color(0xFF5A4A8A),
                  ),
                ),
                calendarStyle: CalendarStyle(
                  selectedDecoration: BoxDecoration(
                    gradient: night
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFFFFD98A), Color(0xFFF8A8C8)]),
                    color: night ? const Color(0xFFF5C518) : null,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: TextStyle(
                    color: night ? const Color(0xFF0B0E14) : const Color(0xFF7A4A10),
                    fontWeight: FontWeight.w700,
                  ),
                  todayDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                ),
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    final types = events.map((e) => e.type).toSet().take(3);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: types
                          .map((t) => Container(
                                width: 5,
                                height: 5,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  color: eventTypeColor(t.label, night),
                                  shape: night
                                      ? BoxShape.rectangle
                                      : BoxShape.circle,
                                ),
                              ))
                          .toList(),
                    );
                  },
                ),
              ),
            ),
          ),

          // 当日列表（按游戏分组，可展开/收起）
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(
              '${selected.month}月${selected.day}日 更新',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: night ? const Color(0xFFEEF2F8) : Colors.white,
              ),
            ),
          ),
          GroupedDayEvents(events: _dayEvents(byDay, selected)),
          if (_dayEvents(byDay, selected).isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  '这一天风平浪静，没有游戏更新 ✨',
                  style: TextStyle(
                    color: night ? const Color(0xFF5A6373) : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<UpdateEvent> _dayEvents(
      AsyncValue<Map<DateTime, List<UpdateEvent>>> byDay, DateTime day) {
    final map = byDay.valueOrNull ?? {};
    return map[DateTime(day.year, day.month, day.day)] ?? [];
  }
}

/// 当日事件按游戏分组 + 展开/收起
class GroupedDayEvents extends ConsumerStatefulWidget {
  final List<UpdateEvent> events;
  const GroupedDayEvents({super.key, required this.events});

  @override
  ConsumerState<GroupedDayEvents> createState() => _GroupedDayEventsState();
}

class _GroupedDayEventsState extends ConsumerState<GroupedDayEvents> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    // 按游戏分组，保持游戏注册表顺序
    final grouped = <String, List<UpdateEvent>>{};
    for (final e in widget.events) {
      grouped.putIfAbsent(e.gameId, () => []).add(e);
    }
    final gameIds = GameRegistry.games
        .map((g) => g.id)
        .where(grouped.containsKey)
        .toList();

    return Column(
      children: [
        for (final gid in gameIds)
          _buildGroup(context, GameRegistry.byId(gid), grouped[gid]!, night),
      ],
    );
  }

  Widget _buildGroup(
      BuildContext context, dynamic game, List<UpdateEvent> events, bool night) {
    final collapsed = _collapsed.contains(game.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(night ? 6 : 22),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GameDetailPage(gameId: game.id)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  GameAvatar(game, size: 34, round: night),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      game.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${events.length} 条',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(width: 4),
                  // 展开/收起按钮（独立于整行的跳转）
                  InkWell(
                    onTap: () => setState(() {
                      collapsed
                          ? _collapsed.remove(game.id)
                          : _collapsed.add(game.id);
                    }),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        collapsed ? Icons.expand_more : Icons.expand_less,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            ...events.map(
              (e) => InkWell(
                onTap: () async {
                  // 优先打开公告原文；无链接则进游戏详情页
                  final ok = await openLink(e.url);
                  if (!ok && context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => GameDetailPage(gameId: e.gameId)),
                    );
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            if (e.summary.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                e.summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      EventTypeTag(e.type),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

/// 游戏列表页
class GamesView extends ConsumerWidget {
  const GamesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    final enabled = ref.watch(enabledGamesProvider);
    final games = GameRegistry.games.where((g) => enabled.contains(g.id));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            '我的游戏（${games.length}）',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: night ? const Color(0xFFEEF2F8) : Colors.white,
            ),
          ),
        ),
        ...games.map(
          (g) => Card(
            child: ListTile(
              leading: GameAvatar(g, round: night),
              title: Text(g.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(g.placeholder ? '预约中' : '点击查看公告 / 卡池 / 活动'),
              trailing: const Icon(Icons.chevron_right),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(night ? 6 : 22)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GameDetailPage(gameId: g.id)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

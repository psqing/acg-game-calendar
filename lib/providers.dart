import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/repository.dart';
import 'models.dart';

final repositoryProvider = Provider<EventRepository>((ref) {
  throw UnimplementedError('override in main');
});

/// 日夜模式
class NightModeNotifier extends StateNotifier<bool> {
  final EventRepository repo;
  NightModeNotifier(this.repo) : super(repo.isNightMode());

  Future<void> toggle() async {
    state = !state;
    await repo.setNightMode(state);
  }
}

final nightModeProvider =
    StateNotifierProvider<NightModeNotifier, bool>((ref) {
  return NightModeNotifier(ref.watch(repositoryProvider));
});

/// 启用的游戏 id 列表
class EnabledGamesNotifier extends StateNotifier<List<String>> {
  final EventRepository repo;
  EnabledGamesNotifier(this.repo) : super(repo.enabledGameIds());

  Future<void> toggle(String gameId) async {
    final next = [...state];
    next.contains(gameId) ? next.remove(gameId) : next.add(gameId);
    state = next;
    await repo.setEnabledGameIds(next);
  }
}

final enabledGamesProvider =
    StateNotifierProvider<EnabledGamesNotifier, List<String>>((ref) {
  return EnabledGamesNotifier(ref.watch(repositoryProvider));
});

/// 强制刷新触发器
final refreshTriggerProvider = StateProvider<int>((ref) => 0);

/// 全部事件（带缓存 + 筛选）
final eventsProvider = FutureProvider<List<UpdateEvent>>((ref) async {
  ref.watch(refreshTriggerProvider);
  final ids = ref.watch(enabledGamesProvider);
  final repo = ref.watch(repositoryProvider);
  final events = await repo.getEvents(
    gameIds: ids,
    forceRefresh: ref.read(refreshTriggerProvider) > 0,
  );
  // 同步抓取状态供设置页自检
  ref.read(fetchStatusProvider.notifier).state = repo.fetchStatuses();
  return events;
});

/// 各数据源最近一次抓取状态（ok:n / empty / error:msg）
final fetchStatusProvider = StateProvider<Map<String, String>>((ref) => {});

/// 日历当前选中日期
final selectedDayProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// 按日期分组的事件 Map（供日历 eventLoader 使用）
final eventsByDayProvider =
    Provider<AsyncValue<Map<DateTime, List<UpdateEvent>>>>((ref) {
  final async = ref.watch(eventsProvider);
  return async.whenData((events) {
    final map = <DateTime, List<UpdateEvent>>{};
    for (final e in events) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      map.putIfAbsent(day, () => []).add(e);
    }
    return map;
  });
});

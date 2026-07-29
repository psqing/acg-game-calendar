import 'package:hive_flutter/hive_flutter.dart';

import '../models.dart';
import 'games.dart';
import 'sources.dart';

/// 仓库层：缓存优先 + 过期刷新 + 失败回退
class EventRepository {
  static const _cacheBox = 'cache';
  static const _prefsBox = 'prefs';
  static const _ttl = Duration(hours: 6);

  late Box _cache;
  late Box _prefs;

  Future<void> init() async {
    await Hive.initFlutter();
    _cache = await Hive.openBox(_cacheBox);
    _prefs = await Hive.openBox(_prefsBox);
  }

  // ---------- 游戏筛选 ----------

  List<String> enabledGameIds() {
    final raw = _prefs.get('enabled_games');
    if (raw == null) {
      // 默认全开
      return GameRegistry.games.map((g) => g.id).toList();
    }
    return (raw as List).cast<String>();
  }

  Future<void> setEnabledGameIds(List<String> ids) =>
      _prefs.put('enabled_games', ids);

  // ---------- 主题 ----------

  bool isNightMode() => _prefs.get('night_mode', defaultValue: false) as bool;
  Future<void> setNightMode(bool v) => _prefs.put('night_mode', v);

  // ---------- 事件缓存 ----------

  String _key(String gameId) => 'events_$gameId';
  String _tsKey(String gameId) => 'ts_$gameId';

  List<UpdateEvent>? _cached(String gameId) {
    final s = _cache.get(_key(gameId));
    if (s is! String || s.isEmpty) return null;
    try {
      return UpdateEvent.decodeList(s);
    } catch (_) {
      return null;
    }
  }

  bool _fresh(String gameId) {
    final ts = _cache.get(_tsKey(gameId));
    if (ts is! int) return false;
    return DateTime.now().millisecondsSinceEpoch - ts < _ttl.inMilliseconds;
  }

  // ---------- 抓取状态自检 ----------

  Map<String, String> fetchStatuses() {
    final raw = _prefs.get('fetch_statuses');
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Future<void> _setStatus(String gameId, String status) async {
    final map = fetchStatuses();
    map[gameId] = status;
    await _prefs.put('fetch_statuses', map);
  }

  /// 获取全部启用游戏的事件；forceRefresh 时忽略 TTL
  Future<List<UpdateEvent>> getEvents({
    List<String>? gameIds,
    bool forceRefresh = false,
  }) async {
    final ids = gameIds ?? enabledGameIds();
    final result = <UpdateEvent>[];
    for (final id in ids) {
      final game = GameRegistry.byId(id);
      if (!forceRefresh && _fresh(id)) {
        result.addAll(_cached(id) ?? []);
        continue;
      }
      try {
        final events = await sourceFor(game).fetch(game);
        if (events.isNotEmpty) {
          await _cache.put(_key(id), UpdateEvent.encodeList(events));
          await _cache.put(
              _tsKey(id), DateTime.now().millisecondsSinceEpoch);
          result.addAll(events);
          await _setStatus(id, 'ok:${events.length}');
        } else {
          // 抓空：回退缓存，再回退 mock
          result.addAll(
              _cached(id) ?? await MockSource().fetch(game));
          await _setStatus(id, 'empty');
        }
      } catch (e) {
        result.addAll(_cached(id) ?? await MockSource().fetch(game));
        await _setStatus(id, 'error:${e.toString()}');
      }
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  Future<void> clearCache() => _cache.clear();
}

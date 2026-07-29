import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/games.dart';
import '../providers.dart';
import 'widgets.dart';

/// 设置页：游戏筛选 / 缓存管理 / 说明
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    final enabled = ref.watch(enabledGamesProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            '设置',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: night ? const Color(0xFFEEF2F8) : Colors.white,
            ),
          ),
        ),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text('游戏筛选（勾选的才会出现在日历）',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              ...GameRegistry.games.map(
                (g) => CheckboxListTile(
                  value: enabled.contains(g.id),
                  onChanged: (_) =>
                      ref.read(enabledGamesProvider.notifier).toggle(g.id),
                  secondary: GameAvatar(g, size: 36, round: night),
                  title: Text(g.name, style: const TextStyle(fontSize: 14)),
                  subtitle: _statusText(ref, g),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('全部重新抓取（自检）'),
                subtitle: const Text('抓取结果会显示在每个游戏下方'),
                onTap: () async {
                  ref.read(refreshTriggerProvider.notifier).state++;
                  await ref.read(eventsProvider.future);
                  if (context.mounted) {
                    final st = ref.read(fetchStatusProvider);
                    final ok = st.values.where((v) => v.startsWith('ok')).length;
                    final bad = st.length - ok;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('抓取完成：$ok 个成功，$bad 个异常，详情见各游戏下方')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('清空缓存并重新抓取'),
                subtitle: const Text('公告缓存 6 小时自动过期'),
                onTap: () async {
                  await ref.read(repositoryProvider).clearCache();
                  ref.read(refreshTriggerProvider.notifier).state++;
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('缓存已清空，正在重新抓取')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '数据来源：米哈游系 = 米游社官方分区；明日方舟/阴阳师 = 官网解析；鸣潮/战双/Nikke 校准中。\n'
              '若米哈游系也全部失败，请检查设备网络是否能访问 miyoushe.com。\n'
              '单人使用工具，数据版权归各游戏官方所有。',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  /// 每个游戏下方显示数据源自检状态
  Widget? _statusText(WidgetRef ref, dynamic g) {
    if (g.placeholder) {
      return const Text('预约中', style: TextStyle(fontSize: 11));
    }
    final st = ref.watch(fetchStatusProvider)[g.id];
    if (st == null) return null;
    if (st.startsWith('ok:')) {
      return Text('✅ 抓取正常 · ${st.substring(3)} 条',
          style: const TextStyle(fontSize: 11, color: Colors.green));
    }
    if (st == 'empty') {
      return const Text('⚠️ 抓取为空（官网结构可能已变动）',
          style: TextStyle(fontSize: 11, color: Colors.orange));
    }
    if (st.startsWith('error:')) {
      var msg = st.substring(6);
      if (msg.length > 60) msg = '${msg.substring(0, 60)}…';
      return Text('❌ $msg',
          style: const TextStyle(fontSize: 11, color: Colors.red));
    }
    return null;
  }
}

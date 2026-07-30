import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/games.dart';
import '../models.dart';
import '../providers.dart';
import 'widgets.dart';

/// 游戏详情页：沉浸式主题 + 宣传图头图 + 公告/卡池/活动 Tab
class GameDetailPage extends ConsumerWidget {
  final String gameId;
  const GameDetailPage({super.key, required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = GameRegistry.byId(gameId);
    final primary = Color(game.primaryColor);
    final secondary = Color(game.secondaryColor);
    final eventsAsync = ref.watch(eventsProvider);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: primary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(game.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
              background: eventsAsync.when(
                data: (all) {
                  final covers = all
                      .where((e) => e.gameId == gameId && e.cover != null)
                      .toList()
                    ..sort((a, b) => b.date.compareTo(a.date));
                  final cover =
                      covers.isNotEmpty ? covers.first.cover! : null;
                  return _headerBg(game, primary, secondary, cover);
                },
                loading: () => _headerBg(game, primary, secondary, null),
                error: (_, __) => _headerBg(game, primary, secondary, null),
              ),
            ),
          ),
        ],
        body: eventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('数据加载失败，下拉首页刷新重试')),
          data: (all) {
            // 合并为单条时间线，按日期倒序（最新在上）
            final mine = all.where((e) => e.gameId == gameId).toList()
              ..sort((a, b) => b.date.compareTo(a.date));
            if (mine.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(game.mascot, style: const TextStyle(fontSize: 64)),
                    const SizedBox(height: 12),
                    const Text('暂无数据',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: mine.length,
              itemBuilder: (context, i) => EventCard(
                mine[i],
                onTap: () => openLink(context, mine[i].url),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 头图：有宣传图显示宣传图，无则用游戏图标放大，再无则 emoji
  Widget _headerBg(Game game, Color primary, Color secondary, String? cover) {
    final gradient = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, secondary],
        ),
      ),
    );
    if (cover != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: cover,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => gradient,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.35),
                  primary.withOpacity(0.55),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final icon = game.iconUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        gradient,
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null)
                CachedNetworkImage(
                  imageUrl: icon,
                  width: 110,
                  height: 110,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Text(game.mascot,
                      style: const TextStyle(fontSize: 72, color: Colors.white70)),
                )
              else
                Text(game.mascot,
                    style: TextStyle(
                        fontSize: 72, color: Colors.white.withOpacity(0.45))),
              const SizedBox(height: 12),
              Text(
                game.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

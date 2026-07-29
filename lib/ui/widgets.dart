import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../data/games.dart';

/// 打开公告原文链接（外部浏览器）
Future<bool> openLink(String? url) async {
  if (url == null || url.isEmpty) return false;
  try {
    return await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// 游戏头像：优先官方 APP 图标，加载失败回退汉字块
class GameAvatar extends StatelessWidget {
  final Game game;
  final double size;
  final bool round;

  const GameAvatar(this.game, {super.key, this.size = 46, this.round = false});

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(round ? 4 : size * 0.3);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(game.primaryColor), Color(game.secondaryColor)],
        ),
        borderRadius: radius,
        border: night ? Border.all(color: const Color(0xFF232A36)) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        game.short,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
    final url = game.iconUrl;
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

/// 事件类型小标签
class EventTypeTag extends StatelessWidget {
  final EventType type;
  const EventTypeTag(this.type, {super.key});

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final color = switch (type) {
      EventType.version => night ? const Color(0xFFF5C518) : const Color(0xFFF0A83A),
      EventType.banner => const Color(0xFFB08AE0),
      EventType.event => night ? const Color(0xFF22D3EE) : const Color(0xFFF06A9A),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: night ? Colors.transparent : color.withOpacity(0.18),
        border: night ? Border.all(color: color) : null,
        borderRadius: BorderRadius.circular(night ? 2 : 999),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: night ? color : color.withOpacity(0.95),
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// 单条事件卡片
class EventCard extends StatelessWidget {
  final UpdateEvent event;
  final VoidCallback? onTap;

  const EventCard(this.event, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final game = GameRegistry.byId(event.gameId);
    final night = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(night ? 6 : 22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GameAvatar(game, size: 44, round: night),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.name,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    if (event.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withOpacity(0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              EventTypeTag(event.type),
            ],
          ),
        ),
      ),
    );
  }
}

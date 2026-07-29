import 'package:flutter/material.dart';

/// 日间主题 = 风格 A（明亮幻想系）
ThemeData dayTheme() {
  const seed = Color(0xFF7A5AC8);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: seed,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFFF3EEF9),
    cardTheme: CardTheme(
      color: Colors.white.withOpacity(0.92),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

/// 夜间主题 = 风格 B（深色科幻系）
ThemeData nightTheme() {
  const accent = Color(0xFFF5C518);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      surface: const Color(0xFF12161F),
    ),
    scaffoldBackgroundColor: const Color(0xFF0B0E14),
    cardTheme: CardTheme(
      color: const Color(0xFF12161F),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFF232A36)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

/// 日间首页背景（明亮幻想渐变）
const dayGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF8FB8E8), Color(0xFFB8A8E0), Color(0xFFE8C8E0), Color(0xFFF8DCC8)],
);

/// 夜间首页背景（深色科幻）
const nightGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF0B0E14), Color(0xFF10151F)],
);

/// 事件类型配色（日历圆点 / 标签）
Color eventTypeColor(String typeLabel, bool night) {
  switch (typeLabel) {
    case '版本':
      return night ? const Color(0xFFF5C518) : const Color(0xFFF0A83A);
    case '卡池':
      return const Color(0xFFB08AE0);
    default:
      return night ? const Color(0xFF22D3EE) : const Color(0xFFF06A9A);
  }
}

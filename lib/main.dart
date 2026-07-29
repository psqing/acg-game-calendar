import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/repository.dart';
import 'providers.dart';
import 'theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  final repo = EventRepository();
  await repo.init();

  runApp(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const AcgCalendarApp(),
    ),
  );
}

class AcgCalendarApp extends ConsumerWidget {
  const AcgCalendarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    return MaterialApp(
      title: '二游日历',
      debugShowCheckedModeBanner: false,
      theme: dayTheme(),
      darkTheme: nightTheme(),
      themeMode: night ? ThemeMode.dark : ThemeMode.light,
      home: const MainShell(),
    );
  }
}

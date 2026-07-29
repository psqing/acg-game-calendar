import '../lib/data/games.dart';
import '../lib/data/sources.dart';
import '../lib/models.dart';

Future<void> main() async {
  for (final game in GameRegistry.games) {
    final src = sourceFor(game);
    try {
      final events = await src.fetch(game);
      print('${game.name} [${src.runtimeType}] -> ${events.length} 条');
      for (final e in events.take(3)) {
        print('   [${e.type.label}] ${e.title} | ${e.date}');
      }
    } catch (e, st) {
      print('${game.name} [${src.runtimeType}] !! 异常: $e');
      print(st.toString().split('\n').take(3).join('\n'));
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('appDatabaseProvider must be overridden by app composition');
});

final appDatabaseLifecycleProvider = StreamProvider<DatabaseLifecycleState>((
  ref,
) async* {
  final database = ref.watch(appDatabaseProvider);
  yield database.state;
  yield* database.states;
});

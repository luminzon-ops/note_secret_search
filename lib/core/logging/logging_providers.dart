import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';

final loggerProvider = Provider<AppLogger>((ref) {
  throw StateError('loggerProvider must be overridden by app composition');
});

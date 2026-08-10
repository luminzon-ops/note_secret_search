import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';

final databaseSessionKeyStoreProvider = Provider<DatabaseSessionKeyStore>((
  ref,
) {
  throw StateError(
    'databaseSessionKeyStoreProvider must be overridden by app composition',
  );
});

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  throw StateError(
    'cryptoServiceProvider must be overridden by app composition',
  );
});

final sensitiveStateAccessAllowedProvider = StateProvider<bool>((ref) => false);

FutureOr<T> guardSensitiveFuture<T>(
  Ref ref, {
  required T lockedValue,
  required Future<T> Function() load,
}) {
  if (!ref.watch(sensitiveStateAccessAllowedProvider)) {
    return lockedValue;
  }
  return load();
}

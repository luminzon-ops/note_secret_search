import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/logging/logging_providers.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/core/storage/database/sqlcipher_database.dart';

final List<Override> coreCompositionOverrides = <Override>[
  loggerProvider.overrideWithValue(const AppLogger()),
  databaseSessionKeyStoreProvider.overrideWith((ref) {
    final store = DatabaseSessionKeyStore();
    ref.onDispose(store.clear);
    return store;
  }),
  cryptoServiceProvider.overrideWith((ref) {
    return AesGcmFieldCrypto(
      sessionKeyStore: ref.watch(databaseSessionKeyStoreProvider),
    );
  }),
  appDatabaseProvider.overrideWith((ref) {
    final database = SqlCipherAppDatabase(logger: ref.watch(loggerProvider));
    ref.onDispose(() => unawaited(database.close()));
    return database;
  }),
];

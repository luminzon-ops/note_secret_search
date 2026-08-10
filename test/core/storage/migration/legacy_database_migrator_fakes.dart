part of 'legacy_database_migrator_test.dart';

class _FfiMigrationDatabaseFactory implements MigrationDatabaseFactory {
  const _FfiMigrationDatabaseFactory();

  @override
  Future<Database> openLegacyForCheckpoint({
    required String path,
    required String password,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: false, singleInstance: false),
    );
  }

  @override
  Future<Database> openLegacy({
    required String path,
    required String password,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
  }

  @override
  Future<Database> openPending({
    required String path,
    required String password,
    required int version,
    required OnDatabaseCreateFn onCreate,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        singleInstance: false,
      ),
    );
  }
}

class _MigrationHarness {
  _MigrationHarness({
    bool corruptNoteContent = false,
    MigrationDatabaseFactory databaseFactory =
        const _FfiMigrationDatabaseFactory(),
  }) : keys = DatabaseSessionKeys(
         databaseKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
         fieldKey: Uint8List.fromList(List<int>.generate(32, (i) => 0x80 + i)),
       ) {
    keyStore.replace(keys);
    crypto = AesGcmFieldCrypto(sessionKeyStore: keyStore);
    migrator = LegacyDatabaseMigrator(
      databaseFactory: databaseFactory,
      cryptoService: corruptNoteContent
          ? _CorruptingCryptoService(crypto)
          : crypto,
      now: () => DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000),
    );
  }

  final DatabaseSessionKeyStore keyStore = DatabaseSessionKeyStore();
  final DatabaseSessionKeys keys;
  late final AesGcmFieldCrypto crypto;
  late final LegacyDatabaseMigrator migrator;

  void dispose() {
    keyStore.clear();
  }
}

class _NonSecretCorruptingMigrationDatabaseFactory
    implements MigrationDatabaseFactory {
  const _NonSecretCorruptingMigrationDatabaseFactory();

  static const _delegate = _FfiMigrationDatabaseFactory();

  @override
  Future<Database> openLegacyForCheckpoint({
    required String path,
    required String password,
  }) {
    return _delegate.openLegacyForCheckpoint(path: path, password: password);
  }

  @override
  Future<Database> openLegacy({
    required String path,
    required String password,
  }) {
    return _delegate.openLegacy(path: path, password: password);
  }

  @override
  Future<Database> openPending({
    required String path,
    required String password,
    required int version,
    required OnDatabaseCreateFn onCreate,
  }) async {
    final database = await _delegate.openPending(
      path: path,
      password: password,
      version: version,
      onCreate: onCreate,
    );
    await database.execute('''
      CREATE TRIGGER corrupt_secret_title
      AFTER INSERT ON secret_items
      WHEN NEW.id = 'secret-1'
      BEGIN
        UPDATE secret_items
        SET title = 'changed after copy'
        WHERE id = NEW.id;
      END
    ''');
    return database;
  }
}

class _CorruptingCryptoService implements CryptoService {
  const _CorruptingCryptoService(this.delegate);

  final CryptoService delegate;

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    final value =
        context.table == 'note_items' &&
            context.rowId == 'note-1' &&
            context.column == 'content_ciphertext'
        ? '$plaintext changed'
        : plaintext;
    return delegate.encryptNullable(value, context: context);
  }

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return delegate.decryptNullable(ciphertext, context: context);
  }
}

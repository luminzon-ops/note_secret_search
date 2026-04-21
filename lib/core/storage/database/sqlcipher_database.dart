import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/database_key_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqlCipherAppDatabase implements AppDatabase {
  SqlCipherAppDatabase({
    required AppLogger logger,
    required DatabaseKeyProvider databaseKeyProvider,
  })  : _logger = logger,
        _databaseKeyProvider = databaseKeyProvider;

  final AppLogger _logger;
  final DatabaseKeyProvider _databaseKeyProvider;
  bool _initialized = false;
  Database? _database;

  static const _databaseName = 'note_secret_search.db';

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, _databaseName);
    final databasePassword = await _databaseKeyProvider.getDatabasePassword();
    _database = await openDatabase(
      path,
      password: databasePassword,
      version: 1,
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final statement in DatabaseMigrations.initial()) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
    );

    await ensureDefaultVault();
    _logger.info('Initialized SQLCipher database at $path with native password material');
    _initialized = true;
  }

  @override
  Future<void> executeBatch(List<String> statements) async {
    final db = await database;
    final batch = db.batch();
    for (final statement in statements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
    _logger.info('Executed ${statements.length} SQLCipher statements');
  }

  @override
  Future<Database> get database async {
    if (_database == null) {
      await initialize();
    }

    return _database!;
  }

  @override
  Future<void> ensureDefaultVault() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      DatabaseSchema.vaults,
      <String, Object?>{
        'id': 'default',
        'name': '默认保险库',
        'description': '首版默认保险库',
        'is_default': 1,
        'encryption_version': 1,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initialized = false;
  }
}

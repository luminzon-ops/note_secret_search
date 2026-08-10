import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const testModelCatalogDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, Object?> trustedModelRegistryRow({
  required String id,
  String type = 'embedding',
  String provider = 'local',
  String name = 'Embedding',
  String? version,
  String? quantization,
  String? checksum,
  bool enabled = true,
}) {
  return <String, Object?>{
    'id': id,
    'type': type,
    'provider': provider,
    'name': name,
    if (version != null) 'version': version,
    if (quantization != null) 'quantization': quantization,
    if (checksum != null) 'checksum': checksum,
    'integrity_status': 'valid',
    'enabled': enabled ? 1 : 0,
    'active_release_id': 'test-release',
    'catalog_version': 1,
    'catalog_digest': testModelCatalogDigest,
    'install_generation': 1,
    'revision_root': 'revisions/1',
  };
}

Future<TestAppDatabase> openTestAppDatabase({
  void Function(SqfliteLoggerEvent event)? onDatabaseEvent,
}) async {
  sqfliteFfiInit();
  final manager = DatabaseSchemaManager();
  final factory = onDatabaseEvent == null
      ? databaseFactoryFfi
      // The logger wrapper is experimental but is the package's public test API.
      // ignore: experimental_member_use
      : SqfliteDatabaseFactoryLogger(
          databaseFactoryFfi,
          options: SqfliteLoggerOptions(log: onDatabaseEvent),
        );
  final database = await factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: manager.version,
      onConfigure: manager.configure,
      onCreate: manager.create,
      onUpgrade: manager.upgrade,
      onDowngrade: manager.downgrade,
      singleInstance: false,
    ),
  );
  await manager.validate(database);
  return TestAppDatabase(database);
}

class TestAppDatabase implements AppDatabase {
  TestAppDatabase(this._database);

  final Database _database;
  DatabaseLifecycleState _state = const DatabaseLifecycleState(
    status: DatabaseLifecycleStatus.open,
  );

  @override
  DatabaseLifecycleState get state => _state;

  @override
  Stream<DatabaseLifecycleState> get states => const Stream.empty();

  @override
  Future<void> open(DatabaseSessionKeys sessionKeys) async {
    if (_state.status != DatabaseLifecycleStatus.open) {
      throw const DatabaseLifecycleException('database_invalid_transition');
    }
  }

  @override
  Future<T> run<T>(Future<T> Function(Database database) operation) async {
    if (_state.status != DatabaseLifecycleStatus.open) {
      throw const DatabaseAccessRevokedException();
    }
    return operation(_database);
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(DatabaseExecutor executor) operation,
  ) async {
    if (_state.status != DatabaseLifecycleStatus.open) {
      throw const DatabaseAccessRevokedException();
    }
    return _database.transaction(operation);
  }

  @override
  Future<void> close() async {
    if (_state.status == DatabaseLifecycleStatus.locked) {
      return;
    }
    _state = const DatabaseLifecycleState(
      status: DatabaseLifecycleStatus.closing,
    );
    await _database.close();
    _state = const DatabaseLifecycleState.locked();
  }
}

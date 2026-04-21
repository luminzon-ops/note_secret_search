import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';

class AppBootstrapService {
  AppBootstrapService({
    required AppDatabase database,
    required SecurityOrchestrator securityOrchestrator,
    required AppLogger logger,
  })  : _database = database,
        _securityOrchestrator = securityOrchestrator,
        _logger = logger;

  final AppDatabase _database;
  final SecurityOrchestrator _securityOrchestrator;
  final AppLogger _logger;

  Future<void> bootstrap() async {
    _logger.info('Bootstrapping application');
    await _securityOrchestrator.initialize();
    await _database.initialize();
    await _database.executeBatch(DatabaseMigrations.initial());
    await _database.ensureDefaultVault();
  }
}

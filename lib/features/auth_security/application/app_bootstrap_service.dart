import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';

class AppBootstrapService {
  AppBootstrapService({
    required SecurityOrchestrator securityOrchestrator,
    required AppLogger logger,
  }) : _securityOrchestrator = securityOrchestrator,
       _logger = logger;

  final SecurityOrchestrator _securityOrchestrator;
  final AppLogger _logger;

  Future<void> bootstrap() async {
    _logger.info('app_bootstrap_started');
    await _securityOrchestrator.initialize();
  }
}

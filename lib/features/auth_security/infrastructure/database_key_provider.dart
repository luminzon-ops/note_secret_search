import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';

abstract interface class DatabaseKeyProvider {
  Future<String> getDatabasePassword();
}

class NativeDatabaseKeyProvider implements DatabaseKeyProvider {
  NativeDatabaseKeyProvider({required SecureKeyGateway secureKeyGateway})
      : _secureKeyGateway = secureKeyGateway;

  final SecureKeyGateway _secureKeyGateway;

  @override
  Future<String> getDatabasePassword() {
    return _secureKeyGateway.getDatabasePasswordMaterial();
  }
}

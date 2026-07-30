import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/shared_preferences_legacy_pin_migration_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'legacy_security_migration_orchestrator_fakes.dart';
part 'legacy_security_migration_orchestrator_order_cases.dart';
part 'legacy_security_migration_orchestrator_resume_cases.dart';

void main() {
  _registerLegacySecurityMigrationOrderCases();
  _registerLegacySecurityMigrationResumeCases();
}

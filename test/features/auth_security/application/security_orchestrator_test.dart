import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

part 'security_orchestrator_bootstrap_migration_cases.dart';
part 'security_orchestrator_fakes.dart';
part 'security_orchestrator_harness.dart';
part 'security_orchestrator_lock_cleanup_cases.dart';
part 'security_orchestrator_race_failure_cases.dart';
part 'security_orchestrator_unlock_order_cases.dart';

void main() {
  _registerSecurityBootstrapMigrationCases();
  _registerSecurityUnlockOrderCases();
  _registerSecurityRaceFailureCases();
  _registerSecurityLockCleanupCases();
}

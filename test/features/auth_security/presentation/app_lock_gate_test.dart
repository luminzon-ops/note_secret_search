import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/router/app_lock_route_gate.dart';
import 'package:note_secret_search/app/router/lock_route_guard.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';
import 'package:note_secret_search/features/auth_security/presentation/pin_unlock_page.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/domain/security_settings_repository.dart';
import 'package:note_secret_search/features/settings/presentation/pin_setup_page.dart';

import '../../../support/fake_app_database.dart';

part 'app_lock_gate_fakes.dart';
part 'app_lock_gate_harness.dart';
part 'app_lock_gate_lifecycle_shield_cases.dart';
part 'app_lock_gate_provision_migration_cases.dart';
part 'app_lock_gate_routing_pin_cases.dart';

void main() {
  _registerAppLockProvisionMigrationCases();
  _registerAppLockLifecycleShieldCases();
  _registerAppLockRoutingPinCases();
}

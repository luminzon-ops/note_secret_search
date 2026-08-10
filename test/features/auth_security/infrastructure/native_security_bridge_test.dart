import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';

part 'native_security_bridge_fakes.dart';
part 'native_security_bridge_harness.dart';
part 'native_security_bridge_migration_path_cases.dart';
part 'native_security_bridge_operations_cases.dart';
part 'native_security_bridge_state_decode_cases.dart';
part 'native_security_bridge_unlock_decode_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('note_secret_search/native_security');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  _registerNativeSecurityStateDecodeCases(
    channel: channel,
    messenger: messenger,
  );
  _registerNativeSecurityMigrationContractCases(
    channel: channel,
    messenger: messenger,
  );
  _registerNativeSecurityUnlockDecodeCases(
    channel: channel,
    messenger: messenger,
  );
  _registerNativeSecurityOperationCases(channel: channel, messenger: messenger);
  _registerNativeSecurityMigrationPathCases();
  _registerNativeSecurityExceptionMappingCases(
    channel: channel,
    messenger: messenger,
  );
}

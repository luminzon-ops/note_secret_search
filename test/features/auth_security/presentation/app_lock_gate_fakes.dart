part of 'app_lock_gate_test.dart';

class _FakeBiometricGateway implements BiometricGateway {
  @override
  Future<bool> authenticate() async => false;

  @override
  Future<BiometricAvailability> getAvailability() async =>
      BiometricAvailability.available;
}

class _FakeScreenshotProtectionGateway implements ScreenshotProtectionGateway {
  _FakeScreenshotProtectionGateway({this.onUpdate});

  final Future<void> Function(bool obscured)? onUpdate;
  final List<bool> obscuredUpdates = [];

  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {
    obscuredUpdates.add(obscured);
    await onUpdate?.call(obscured);
  }
}

class _FakeSecureKeyGateway implements SecureKeyGateway {
  _FakeSecureKeyGateway({
    this.pinConfigured = false,
    this.status = NativeSecurityStatus.locked,
    this.systemUnlockFuture,
  });

  bool pinConfigured;
  NativeSecurityStatus status;
  final Future<NativeUnlockResult>? systemUnlockFuture;
  int provisionCalls = 0;

  @override
  Future<void> configurePin({required String pin}) async {
    pinConfigured = true;
  }

  @override
  Future<NativeSecurityState> getSecurityState() async {
    return NativeSecurityState(
      status: status,
      keyId:
          status == NativeSecurityStatus.unprovisioned ||
              status == NativeSecurityStatus.legacyMigrationRequired
          ? null
          : '123e4567-e89b-42d3-a456-426614174000',
      pinConfigured: pinConfigured,
      deviceCredentialAvailable: true,
      strongBiometricAvailable: true,
      securityLevel: KeySecurityLevel.tee,
    );
  }

  @override
  Future<NativeUnlockResult> provisionWithSystemAuth() {
    provisionCalls += 1;
    status = NativeSecurityStatus.locked;
    return unlockWithSystemAuth();
  }

  @override
  Future<NativeUnlockResult> unlockWithSystemAuth() async {
    final pendingResult = systemUnlockFuture;
    if (pendingResult != null) {
      return pendingResult;
    }
    return NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List(32),
      fieldKey: Uint8List(32),
      unlockMethod: 'system',
    );
  }

  @override
  Future<void> removePin() async {
    pinConfigured = false;
  }

  @override
  Future<NativeUnlockResult> unlockWithPin({required String pin}) async {
    if (pin != '2468') {
      throw const NativeSecurityException(
        code: 'PIN_INCORRECT',
        message: null,
        details: null,
      );
    }
    return NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List(32),
      fieldKey: Uint8List(32),
      unlockMethod: 'pin',
    );
  }

  @override
  Future<void> rebindSystemAuthWithPin({required String pin}) async {}
}

class _FakeLegacySecurityMigration implements LegacySecurityMigrationRunner {
  _FakeLegacySecurityMigration({this.onStart});

  final void Function()? onStart;
  int calls = 0;

  @override
  Future<void> startOrResume() async {
    calls += 1;
    onStart?.call();
  }
}

class _FakeSecuritySettingsRepository implements SecuritySettingsRepository {
  SecuritySettings _settings = const SecuritySettings.defaults().copyWith(
    pinEnabled: true,
  );

  @override
  Future<SecuritySettings> load() async => _settings;

  @override
  Future<int> loadAutoLockSeconds() async => _settings.autoLockSeconds;

  @override
  Future<void> save(SecuritySettings settings) async {
    _settings = settings;
  }
}

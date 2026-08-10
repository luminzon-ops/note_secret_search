part of 'native_security_bridge_test.dart';

Map<String, Object?> _migrationStatePayload(String stage) {
  final detected = stage == 'detected';
  return <String, Object?>{
    'stage': stage,
    'keyId': detected ? null : _validKeyId,
    'sourcePath':
        r'E:\app\no_backup\security\migration-v2\backup\note_secret_search.db',
    'pendingPath':
        r'E:\app\no_backup\security\migration-v2\pending\note_secret_search.db',
    'activePath': r'E:\app\databases\note_secret_search.db',
    'sourceDigest': detected ? null : 'a' * 64,
    'pendingDigest': detected ? null : 'b' * 64,
    'activeDigest': detected ? null : 'b' * 64,
  };
}

Map<String, Object?> _validStatePayload() {
  return <String, Object?>{
    'status': 'locked',
    'keyId': _validKeyId,
    'pinConfigured': false,
    'deviceCredentialAvailable': true,
    'strongBiometricAvailable': true,
    'securityLevel': 'tee',
    'systemRebindRequired': false,
    'pinResetRequired': false,
  };
}

Map<String, Object?> _validUnlockPayload() {
  return <String, Object?>{
    'keyId': _validKeyId,
    'databaseKey': Uint8List(32),
    'fieldKey': Uint8List(32),
    'searchIndexFingerprintKey': Uint8List(32),
    'unlockMethod': 'system',
  };
}

const _validKeyId = '123e4567-e89b-42d3-a456-426614174000';

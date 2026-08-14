import 'dart:typed_data';

import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:path/path.dart' as p;

NativeSecurityState parseNativeSecurityState(Object? payload) {
  if (payload is! Map) {
    throw const FormatException('Invalid native security state payload.');
  }
  final status = _parseSecurityStatus(payload['status']);
  return NativeSecurityState(
    status: status,
    keyId: _parseKeyId(
      payload['keyId'],
      requiredForPayload: status == NativeSecurityStatus.locked,
    ),
    pinConfigured: _parseBool(payload['pinConfigured']),
    deviceCredentialAvailable: _parseBool(payload['deviceCredentialAvailable']),
    strongBiometricAvailable: _parseBool(payload['strongBiometricAvailable']),
    securityLevel: _parseSecurityLevel(payload['securityLevel']),
    systemRebindRequired: _parseBool(payload['systemRebindRequired']),
    pinResetRequired: _parseBool(payload['pinResetRequired']),
  );
}

NativeUnlockResult parseNativeUnlockResult(
  Object? payload, {
  String? expectedUnlockMethod,
  bool requireLegacyDatabasePassword = false,
}) {
  if (payload is! Map) {
    throw const FormatException('Invalid native unlock payload.');
  }

  final keyId = payload['keyId'];
  final databaseKey = payload['databaseKey'];
  final fieldKey = payload['fieldKey'];
  final searchIndexFingerprintKey = payload['searchIndexFingerprintKey'];
  final unlockMethod = payload['unlockMethod'];
  final legacyDatabasePassword = payload['legacyDatabasePassword'];
  try {
    if (databaseKey is! Uint8List ||
        fieldKey is! Uint8List ||
        searchIndexFingerprintKey is! Uint8List ||
        databaseKey.length != 32 ||
        fieldKey.length != 32 ||
        searchIndexFingerprintKey.length != 32 ||
        (unlockMethod != 'system' && unlockMethod != 'pin') ||
        (legacyDatabasePassword != null &&
            legacyDatabasePassword is! Uint8List) ||
        (requireLegacyDatabasePassword &&
            (legacyDatabasePassword is! Uint8List ||
                legacyDatabasePassword.isEmpty)) ||
        (expectedUnlockMethod != null &&
            unlockMethod != expectedUnlockMethod)) {
      throw const FormatException('Invalid native unlock payload.');
    }

    return NativeUnlockResult(
      keyId: _parseKeyId(keyId, requiredForPayload: true)!,
      databaseKey: databaseKey,
      fieldKey: fieldKey,
      searchIndexFingerprintKey: searchIndexFingerprintKey,
      unlockMethod: unlockMethod as String,
      legacyDatabasePassword: legacyDatabasePassword as Uint8List?,
    );
  } finally {
    _clearReceivedKey(databaseKey);
    _clearReceivedKey(fieldKey);
    _clearReceivedKey(searchIndexFingerprintKey);
    _clearReceivedKey(legacyDatabasePassword);
  }
}

NativeLegacyMigrationState parseNativeLegacyMigrationState(Object? payload) {
  if (payload is! Map) {
    throw const FormatException('Invalid native migration state payload.');
  }
  final stage = switch (payload['stage']) {
    'detected' => NativeLegacyMigrationStage.detected,
    'keyringReady' => NativeLegacyMigrationStage.keyringReady,
    'backupReady' => NativeLegacyMigrationStage.backupReady,
    'pendingCreated' => NativeLegacyMigrationStage.pendingCreated,
    'rowsCopied' => NativeLegacyMigrationStage.rowsCopied,
    'validated' => NativeLegacyMigrationStage.validated,
    'oldMoved' => NativeLegacyMigrationStage.oldMoved,
    'newActivated' => NativeLegacyMigrationStage.newActivated,
    'postSwapValidated' => NativeLegacyMigrationStage.postSwapValidated,
    'cleanupComplete' => NativeLegacyMigrationStage.cleanupComplete,
    _ => throw const FormatException('Unknown native migration stage.'),
  };
  final paths = _parseMigrationPaths(
    source: payload['sourcePath'],
    pending: payload['pendingPath'],
    active: payload['activePath'],
  );
  return NativeLegacyMigrationState(
    stage: stage,
    keyId: _parseKeyId(
      payload['keyId'],
      requiredForPayload: stage != NativeLegacyMigrationStage.detected,
    ),
    sourcePath: paths.source,
    pendingPath: paths.pending,
    activePath: paths.active,
    sourceDigest: _parseDigest(payload['sourceDigest']),
    pendingDigest: _parseDigest(payload['pendingDigest']),
    activeDigest: _parseDigest(payload['activeDigest']),
  );
}

NativeSecurityStatus _parseSecurityStatus(Object? value) {
  return switch (value) {
    'unprovisioned' => NativeSecurityStatus.unprovisioned,
    'legacyMigrationRequired' => NativeSecurityStatus.legacyMigrationRequired,
    'locked' => NativeSecurityStatus.locked,
    'recoveryRequired' => NativeSecurityStatus.recoveryRequired,
    _ => throw const FormatException('Unknown native security status.'),
  };
}

KeySecurityLevel _parseSecurityLevel(Object? value) {
  return switch (value) {
    'strongBox' => KeySecurityLevel.strongBox,
    'tee' => KeySecurityLevel.tee,
    'software' => KeySecurityLevel.software,
    'unknown' => KeySecurityLevel.unknown,
    _ => throw const FormatException('Unknown key security level.'),
  };
}

({String source, String pending, String active}) _parseMigrationPaths({
  required Object? source,
  required Object? pending,
  required Object? active,
}) {
  final values = <String>[
    _parseMigrationPath(source),
    _parseMigrationPath(pending),
    _parseMigrationPath(active),
  ];
  final context = _migrationPathContext(values);
  for (final value in values) {
    if (!context.isAbsolute(value) || context.normalize(value) != value) {
      throw const FormatException('Invalid native migration path.');
    }
  }

  final sourcePath = values[0];
  final pendingPath = values[1];
  final activePath = values[2];
  final sourceDirectory = context.dirname(sourcePath);
  final pendingDirectory = context.dirname(pendingPath);
  final sourceRoot = context.dirname(sourceDirectory);
  final pendingRoot = context.dirname(pendingDirectory);
  final securityRoot = context.dirname(sourceRoot);
  final noBackupRoot = context.dirname(securityRoot);
  final appRoot = context.dirname(noBackupRoot);
  final expectedActivePath = context.join(
    appRoot,
    'databases',
    _databaseFileName,
  );

  if (!context.equals(sourceRoot, pendingRoot) ||
      context.basename(sourceDirectory) != 'backup' ||
      context.basename(pendingDirectory) != 'pending' ||
      context.basename(sourceRoot) != 'migration-v2' ||
      context.basename(securityRoot) != 'security' ||
      context.basename(noBackupRoot) != 'no_backup' ||
      context.basename(sourcePath) != _databaseFileName ||
      context.basename(pendingPath) != _databaseFileName ||
      context.basename(activePath) != _databaseFileName ||
      !context.equals(activePath, expectedActivePath)) {
    throw const FormatException('Invalid native migration path.');
  }

  return (source: sourcePath, pending: pendingPath, active: activePath);
}

p.Context _migrationPathContext(List<String> values) {
  final usesWindows = values.map(_looksLikeWindowsPath).toSet();
  if (usesWindows.length != 1) {
    throw const FormatException('Invalid native migration path.');
  }
  return p.Context(style: usesWindows.single ? p.Style.windows : p.Style.posix);
}

bool _looksLikeWindowsPath(String value) {
  return RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)').hasMatch(value);
}

String _parseMigrationPath(Object? value) {
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw const FormatException('Invalid native migration path.');
  }
  return value;
}

String? _parseDigest(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String || !_sha256Pattern.hasMatch(value)) {
    throw const FormatException('Invalid native migration digest.');
  }
  return value;
}

void _clearReceivedKey(Object? value) {
  if (value is Uint8List) {
    try {
      value.fillRange(0, value.length, 0);
    } on UnsupportedError {
      // StandardMessageCodec can expose platform-owned read-only byte views.
    }
  }
}

String? _parseKeyId(Object? value, {required bool requiredForPayload}) {
  if (value == null) {
    if (requiredForPayload) {
      throw const FormatException('Native security key ID is missing.');
    }
    return null;
  }
  if (value is! String ||
      value != value.trim() ||
      !_canonicalUuidPattern.hasMatch(value)) {
    throw const FormatException('Native security key ID is invalid.');
  }
  return value;
}

bool _parseBool(Object? value) {
  if (value is! bool) {
    throw const FormatException('Invalid native security state payload.');
  }
  return value;
}

final RegExp _canonicalUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
const String _databaseFileName = 'note_secret_search.db';

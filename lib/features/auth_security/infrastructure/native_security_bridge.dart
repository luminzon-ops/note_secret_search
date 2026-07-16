import 'package:flutter/services.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';

abstract interface class NativeSecurityBridge {
  Future<void> enableScreenshotProtection();

  Future<void> updateRecentTaskProtection({required bool obscured});

  Future<NativeSecurityState> getSecurityState();

  Future<NativeUnlockResult> provisionWithSystemAuth({
    String reason = '启用安全存储',
  });

  Future<NativeUnlockResult> unlockWithSystemAuth({String reason = '解锁保险库'});

  Future<void> lock();

  /// Compatibility-only until production orchestration moves to the P2A API.
  Future<void> ensureRootKey();

  /// Compatibility-only until production orchestration moves to the P2A API.
  Future<String> getDatabasePasswordMaterial();

  /// Compatibility-only until production orchestration moves to the P2A API.
  Future<BiometricAvailability> getBiometricAvailability();

  /// Compatibility-only until production orchestration moves to the P2A API.
  Future<bool> authenticateWithBiometrics({String reason = '解锁保险库'});
}

class MethodChannelNativeSecurityBridge implements NativeSecurityBridge {
  const MethodChannelNativeSecurityBridge();

  static const MethodChannel _channel = MethodChannel(
    'note_secret_search/native_security',
  );

  @override
  Future<void> enableScreenshotProtection() async {
    await _invokeMethod<void>('enableScreenshotProtection');
  }

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {
    await _invokeMethod<void>('updateRecentTaskProtection', <String, Object?>{
      'obscured': obscured,
    });
  }

  @override
  Future<NativeSecurityState> getSecurityState() async {
    final payload = await _invokeMethod<Object?>('getSecurityState');
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
      deviceCredentialAvailable: _parseBool(
        payload['deviceCredentialAvailable'],
      ),
      strongBiometricAvailable: _parseBool(payload['strongBiometricAvailable']),
      securityLevel: _parseSecurityLevel(payload['securityLevel']),
    );
  }

  @override
  Future<NativeUnlockResult> provisionWithSystemAuth({
    String reason = '启用安全存储',
  }) async {
    final payload = await _invokeMethod<Object?>(
      'provisionWithSystemAuth',
      <String, Object?>{'reason': reason},
    );
    return parseNativeUnlockResult(payload);
  }

  @override
  Future<NativeUnlockResult> unlockWithSystemAuth({
    String reason = '解锁保险库',
  }) async {
    final payload = await _invokeMethod<Object?>(
      'unlockWithSystemAuth',
      <String, Object?>{'reason': reason},
    );
    return parseNativeUnlockResult(payload);
  }

  @override
  Future<void> lock() async {
    await _invokeMethod<void>('lock');
  }

  // Compatibility-only implementation for pre-P2A callers.
  @override
  Future<void> ensureRootKey() async {
    await _invokeMethod<void>('ensureRootKey');
  }

  // Compatibility-only implementation for pre-P2A callers.
  @override
  Future<String> getDatabasePasswordMaterial() async {
    final value = await _invokeMethod<String>('getDatabasePasswordMaterial');
    final material = value?.trim();
    if (material == null || material.isEmpty) {
      throw StateError('Database key material is unavailable.');
    }
    return material;
  }

  // Compatibility-only implementation for pre-P2A callers.
  @override
  Future<BiometricAvailability> getBiometricAvailability() async {
    final raw = await _invokeMethod<String>('getBiometricAvailability');
    return switch (raw) {
      'available' => BiometricAvailability.available,
      'not_enrolled' => BiometricAvailability.notEnrolled,
      _ => BiometricAvailability.unavailable,
    };
  }

  // Compatibility-only implementation for pre-P2A callers.
  @override
  Future<bool> authenticateWithBiometrics({String reason = '解锁保险库'}) async {
    final result = await _invokeMethod<bool>(
      'authenticateWithBiometrics',
      <String, Object?>{'reason': reason},
    );
    return result ?? false;
  }

  Future<T?> _invokeMethod<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        NativeSecurityException(
          code: error.code,
          message: error.message,
          details: error.details,
        ),
        stackTrace,
      );
    }
  }
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

NativeUnlockResult parseNativeUnlockResult(Object? payload) {
  if (payload is! Map) {
    throw const FormatException('Invalid native unlock payload.');
  }

  final keyId = payload['keyId'];
  final databaseKey = payload['databaseKey'];
  final fieldKey = payload['fieldKey'];
  final unlockMethod = payload['unlockMethod'];
  try {
    if (databaseKey is! Uint8List ||
        fieldKey is! Uint8List ||
        databaseKey.length != 32 ||
        fieldKey.length != 32 ||
        unlockMethod != 'system') {
      throw const FormatException('Invalid native unlock payload.');
    }

    return NativeUnlockResult(
      keyId: _parseKeyId(keyId, requiredForPayload: true)!,
      databaseKey: databaseKey,
      fieldKey: fieldKey,
      unlockMethod: 'system',
    );
  } catch (_) {
    _clearReceivedKey(databaseKey);
    _clearReceivedKey(fieldKey);
    rethrow;
  }
}

void _clearReceivedKey(Object? value) {
  if (value is Uint8List) {
    value.fillRange(0, value.length, 0);
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

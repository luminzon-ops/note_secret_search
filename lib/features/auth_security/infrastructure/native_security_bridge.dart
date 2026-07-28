import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_payload_parser.dart';

export 'package:note_secret_search/features/auth_security/infrastructure/native_security_payload_parser.dart'
    show parseNativeLegacyMigrationState, parseNativeUnlockResult;

abstract interface class NativeSecurityMethodInvoker {
  Future<Object?> invokeMethod(String method, [Object? arguments]);
}

class MethodChannelNativeSecurityBridge
    implements NativeSecurityBridge, NativeSecurityMigrationBridge {
  const MethodChannelNativeSecurityBridge({
    NativeSecurityMethodInvoker invoker =
        const _MethodChannelNativeSecurityMethodInvoker(),
  }) : _invoker = invoker;

  final NativeSecurityMethodInvoker _invoker;

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
    return parseNativeSecurityState(payload);
  }

  @override
  Future<NativeUnlockResult> provisionWithSystemAuth({
    String reason = '启用安全存储',
  }) async {
    final payload = await _invokeMethod<Object?>(
      'provisionWithSystemAuth',
      <String, Object?>{'reason': reason},
    );
    return parseNativeUnlockResult(payload, expectedUnlockMethod: 'system');
  }

  @override
  Future<NativeUnlockResult> unlockWithSystemAuth({
    String reason = '解锁保险库',
  }) async {
    final payload = await _invokeMethod<Object?>(
      'unlockWithSystemAuth',
      <String, Object?>{'reason': reason},
    );
    return parseNativeUnlockResult(payload, expectedUnlockMethod: 'system');
  }

  @override
  Future<void> configurePin({
    required String pin,
    String reason = '配置备用 PIN',
  }) async {
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    try {
      await _invokeMethod<void>('configurePin', <String, Object?>{
        'reason': reason,
        'pin': pinBytes,
      });
    } finally {
      pinBytes.fillRange(0, pinBytes.length, 0);
    }
  }

  @override
  Future<NativeUnlockResult> unlockWithPin({required String pin}) async {
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    try {
      final payload = await _invokeMethod<Object?>(
        'unlockWithPin',
        <String, Object?>{'pin': pinBytes},
      );
      return parseNativeUnlockResult(payload, expectedUnlockMethod: 'pin');
    } finally {
      pinBytes.fillRange(0, pinBytes.length, 0);
    }
  }

  @override
  Future<void> rebindSystemAuthWithPin({
    required String pin,
    String reason = '恢复系统认证',
  }) async {
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    try {
      await _invokeMethod<void>('rebindSystemAuthWithPin', <String, Object?>{
        'reason': reason,
        'pin': pinBytes,
      });
    } finally {
      pinBytes.fillRange(0, pinBytes.length, 0);
    }
  }

  @override
  Future<void> removePin({String reason = '移除备用 PIN'}) async {
    await _invokeMethod<void>('removePin', <String, Object?>{'reason': reason});
  }

  @override
  Future<void> lock() async {
    await _invokeMethod<void>('lock');
  }

  @override
  Future<NativeUnlockResult> beginLegacyMigration({
    String reason = '升级安全存储',
  }) async {
    final payload = await _invokeMethod<Object?>(
      'beginLegacyMigration',
      <String, Object?>{'reason': reason},
    );
    return parseNativeUnlockResult(
      payload,
      expectedUnlockMethod: 'system',
      requireLegacyDatabasePassword: true,
    );
  }

  @override
  Future<NativeLegacyMigrationState> getLegacyMigrationState() {
    return _migrationState('getLegacyMigrationState');
  }

  @override
  Future<NativeLegacyMigrationState> prepareLegacyMigrationBackup(
    String keyId,
  ) {
    return _migrationState('prepareLegacyMigrationBackup', keyId);
  }

  @override
  Future<NativeLegacyMigrationState> prepareLegacyMigrationPending(
    String keyId,
  ) {
    return _migrationState('prepareLegacyMigrationPending', keyId);
  }

  @override
  Future<NativeLegacyMigrationState> markLegacyMigrationRowsCopied(
    String keyId,
  ) {
    return _migrationState('markLegacyMigrationRowsCopied', keyId);
  }

  @override
  Future<NativeLegacyMigrationState> markLegacyMigrationValidated(
    String keyId,
  ) {
    return _migrationState('markLegacyMigrationValidated', keyId);
  }

  @override
  Future<NativeLegacyMigrationState> activateLegacyMigration(String keyId) {
    return _migrationState('activateLegacyMigration', keyId);
  }

  @override
  Future<NativeLegacyMigrationState> markLegacyMigrationPostSwapValidated(
    String keyId,
  ) {
    return _migrationState('markLegacyMigrationPostSwapValidated', keyId);
  }

  @override
  Future<NativeLegacyMigrationState> cleanupLegacyMigrationFiles(String keyId) {
    return _migrationState('cleanupLegacyMigrationFiles', keyId);
  }

  @override
  Future<void> commitLegacyMigration({
    required String keyId,
    required String activeDigest,
  }) async {
    await _invokeMethod<void>('commitLegacyMigration', <String, Object?>{
      'keyId': keyId,
      'activeDigest': activeDigest,
    });
  }

  @override
  Future<void> finishLegacyMigration(String keyId) async {
    await _invokeMethod<void>('finishLegacyMigration', <String, Object?>{
      'keyId': keyId,
    });
  }

  @override
  Future<void> abortLegacyMigration() async {
    await _invokeMethod<void>('abortLegacyMigration');
  }

  Future<NativeLegacyMigrationState> _migrationState(
    String method, [
    String? keyId,
  ]) async {
    final payload = await _invokeMethod<Object?>(
      method,
      keyId == null ? null : <String, Object?>{'keyId': keyId},
    );
    return parseNativeLegacyMigrationState(payload);
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
      return await _invoker.invokeMethod(method, arguments) as T?;
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

class _MethodChannelNativeSecurityMethodInvoker
    implements NativeSecurityMethodInvoker {
  const _MethodChannelNativeSecurityMethodInvoker();

  static const MethodChannel _channel = MethodChannel(
    'note_secret_search/native_security',
  );

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }
}

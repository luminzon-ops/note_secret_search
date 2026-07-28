import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/domain/security_settings_repository.dart';

class SecuritySettingsController
    extends StateNotifier<AsyncValue<SecuritySettings>> {
  SecuritySettingsController({
    required SecuritySettingsRepository repository,
    required SecurityOrchestrator securityOrchestrator,
    required PinStateController pinStateController,
  }) : _repository = repository,
       _securityOrchestrator = securityOrchestrator,
       _pinStateController = pinStateController,
       super(const AsyncLoading()) {
    unawaited(load());
  }

  final SecuritySettingsRepository _repository;
  final SecurityOrchestrator _securityOrchestrator;
  final PinStateController _pinStateController;
  var _loadGeneration = 0;
  var _disposed = false;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    if (_disposed) {
      return;
    }
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() async {
      final settings = await _repository.load();
      final nativeState = await _securityOrchestrator.refreshSecurityState();
      _pinStateController.syncConfigured(nativeState.pinConfigured);
      return settings.copyWith(pinEnabled: nativeState.pinConfigured);
    });
    if (_disposed || generation != _loadGeneration) {
      return;
    }
    state = next;
  }

  Future<void> updatePinEnabled(bool enabled) async {
    final current = _requireLoadedSettings();
    if (enabled) {
      final nativeState = await _securityOrchestrator.refreshSecurityState();
      if (!nativeState.pinConfigured) {
        throw StateError('A PIN must be configured before it can be enabled.');
      }
    } else {
      await _securityOrchestrator.removePin();
    }
    final next = current.copyWith(pinEnabled: enabled);
    await _repository.save(next);
    _publish(next);
  }

  Future<void> setPin(String pin) async {
    final current = _requireLoadedSettings();
    final next = current.copyWith(pinEnabled: true);
    await _securityOrchestrator.configurePin(pin);
    await _repository.save(next);
    _publish(next);
  }

  Future<void> updateAutoLockSeconds(int seconds) async {
    final current = _requireLoadedSettings();
    final next = current.copyWith(autoLockSeconds: seconds);
    await _repository.save(next);
    _publish(next);
  }

  SecuritySettings _requireLoadedSettings() {
    final current = state.valueOrNull;
    if (current == null || state.isLoading || state.hasError) {
      throw StateError('Security settings are not loaded.');
    }
    return current;
  }

  void _publish(SecuritySettings settings) {
    if (!_disposed) {
      state = AsyncData(settings);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration += 1;
    super.dispose();
  }
}

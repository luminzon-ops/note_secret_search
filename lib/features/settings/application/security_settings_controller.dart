import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/security_settings_repository.dart';

class SecuritySettingsController extends StateNotifier<AsyncValue<SecuritySettings>> {
  static const int maxPinFailures = 5;
  static const Duration pinCoolDown = Duration(minutes: 1);

  SecuritySettingsController({
    required SecuritySettingsRepository repository,
    required SecurityOrchestrator securityOrchestrator,
    required PinStateController pinStateController,
  })  : _repository = repository,
        _securityOrchestrator = securityOrchestrator,
        _pinStateController = pinStateController,
        super(const AsyncLoading()) {
    load();
  }

  final SecuritySettingsRepository _repository;
  final SecurityOrchestrator _securityOrchestrator;
  final PinStateController _pinStateController;

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final settings = await _repository.load();
      final hasPinMaterial = await _repository.hasPinMaterial();
      _pinStateController.configureEnabled(settings.pinEnabled);
      if (hasPinMaterial) {
        _pinStateController.markPinMaterialReady();
      }
      return settings;
    });
  }

  Future<void> updatePinEnabled(bool enabled) async {
    final current = state.valueOrNull ?? const SecuritySettings.defaults();
    final next = current.copyWith(pinEnabled: enabled);
    await _repository.save(next);
    _securityOrchestrator.enablePinFallback(enabled);
    state = AsyncData(next);
  }

  Future<void> setPin(String pin) async {
    final current = state.valueOrNull ?? const SecuritySettings.defaults();
    await _repository.savePinMaterial(pin);
    await _repository.save(current.copyWith(pinEnabled: true));
    _securityOrchestrator.enablePinFallback(true);
    _pinStateController.markPinMaterialReady();
    state = AsyncData(current.copyWith(pinEnabled: true));
  }

  Future<bool> verifyPin(String pin) async {
    return _repository.verifyPin(pin);
  }

  Future<void> updateAutoLockSeconds(int seconds) async {
    final current = state.valueOrNull ?? const SecuritySettings.defaults();
    final next = current.copyWith(autoLockSeconds: seconds);
    await _repository.save(next);
    state = AsyncData(next);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';

class PinUnlockPage extends ConsumerStatefulWidget {
  const PinUnlockPage({super.key});

  @override
  ConsumerState<PinUnlockPage> createState() => _PinUnlockPageState();
}

class _PinUnlockPageState extends ConsumerState<PinUnlockPage> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinState = ref.watch(pinStateControllerProvider);
    final coolDownUntil = pinState.coolDownUntil;
    final inCoolDown =
        coolDownUntil != null && coolDownUntil.isAfter(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('PIN 解锁')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('输入应用 PIN 作为备用解锁方式。'),
                    const SizedBox(height: 8),
                    Text(
                      '当前失败次数：${pinState.failedAttempts}/${SecuritySettingsController.maxPinFailures}',
                    ),
                    if (inCoolDown)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '冷却中，结束时间：${coolDownUntil.toLocal()}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '输入 PIN',
                errorText: _errorText,
              ),
              validator: (value) {
                final raw = value ?? '';
                if (raw.length < 4 || raw.length > 8) {
                  return 'PIN 长度需为 4-8 位';
                }
                if (!RegExp(r'^\d+$').hasMatch(raw)) {
                  return 'PIN 仅支持数字';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_submitting || inCoolDown) ? null : _submit,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(_submitting ? '验证中...' : '解锁'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final pin = _pinController.text;
    _pinController.clear();
    try {
      final expectedLockEpoch = ref
          .read(lockSessionControllerProvider)
          .lockEpoch;
      final unlocked = await ref
          .read(securityOrchestratorProvider)
          .unlockWithPin(pin: pin, expectedLockEpoch: expectedLockEpoch);
      if (!unlocked) {
        if (mounted) {
          setState(() {
            _errorText = '安全解锁失败，请重试';
          });
        }
        return;
      }

      if (mounted) {
        final router = GoRouter.maybeOf(context);
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop(true);
        } else if (router != null && router.canPop()) {
          router.pop(true);
        } else if (router != null) {
          router.go('/vault');
        }
      }
    } on NativeSecurityException catch (error) {
      if (error.code == 'PIN_INCORRECT') {
        ref
            .read(securityOrchestratorProvider)
            .registerPinFailure(
              maxFailures: SecuritySettingsController.maxPinFailures,
              coolDown: SecuritySettingsController.pinCoolDown,
            );
      } else if (error.code == 'PIN_COOLDOWN') {
        ref
            .read(securityOrchestratorProvider)
            .registerPinFailure(
              maxFailures: 1,
              coolDown: SecuritySettingsController.pinCoolDown,
            );
      }
      if (mounted) {
        setState(() {
          _errorText = switch (error.code) {
            'PIN_INCORRECT' => 'PIN 错误',
            'PIN_COOLDOWN' => 'PIN 已进入冷却，请稍后重试',
            _ => 'PIN 解锁失败，请重试',
          };
        });
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

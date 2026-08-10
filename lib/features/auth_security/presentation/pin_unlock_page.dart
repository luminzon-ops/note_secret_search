import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_policy.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';

class PinUnlockPage extends ConsumerStatefulWidget {
  const PinUnlockPage({this.onUnlocked, super.key});

  final VoidCallback? onUnlocked;

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
                      '当前失败次数：${pinState.failedAttempts}/${AppPinPolicy.maxFailures}',
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
                return switch (AppPinPolicy.validate(value ?? '')) {
                  PinValidationFailure.invalidLength => 'PIN 长度需为 4-8 位',
                  PinValidationFailure.nonNumeric => 'PIN 仅支持数字',
                  null => null,
                };
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
        final onUnlocked = widget.onUnlocked;
        if (onUnlocked != null) {
          onUnlocked();
          return;
        }
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop(true);
        }
      }
    } on NativeSecurityException catch (error) {
      if (error.code == 'PIN_INCORRECT') {
        ref
            .read(securityOrchestratorProvider)
            .registerPinFailure(
              maxFailures: AppPinPolicy.maxFailures,
              coolDown: AppPinPolicy.coolDown,
            );
      } else if (error.code == 'PIN_COOLDOWN') {
        ref
            .read(securityOrchestratorProvider)
            .registerPinFailure(
              maxFailures: 1,
              coolDown: AppPinPolicy.coolDown,
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
    } on DatabaseLifecycleException {
      if (mounted) {
        setState(() {
          _errorText = '安全数据库暂不可用，请重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

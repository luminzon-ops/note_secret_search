import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

class PinSetupPage extends ConsumerStatefulWidget {
  const PinSetupPage({this.unlockOnSuccess = false, super.key});

  final bool unlockOnSuccess;

  @override
  ConsumerState<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends ConsumerState<PinSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置应用 PIN')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '当前版本仅完成 PIN 备用入口的 MVP 骨架。后续会切换到 Argon2id + KeyStore 包裹设计，避免将 PIN 以当前方式长期存储。',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pinController,
              decoration: const InputDecoration(labelText: '输入 4-8 位 PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              validator: (value) {
                final raw = value?.trim() ?? '';
                if (raw.length < 4 || raw.length > 8) {
                  return 'PIN 长度需为 4-8 位';
                }
                if (!RegExp(r'^\d+$').hasMatch(raw)) {
                  return 'PIN 仅支持数字';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              decoration: const InputDecoration(labelText: '确认 PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              validator: (value) {
                if ((value?.trim() ?? '') != _pinController.text.trim()) {
                  return '两次输入的 PIN 不一致';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(_submitting ? '保存中...' : '保存 PIN'),
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

    setState(() => _submitting = true);
    try {
      final repository = await ref.read(securitySettingsRepositoryProvider.future);
      final currentSettings = await repository.load();
      final nextSettings = currentSettings.copyWith(pinEnabled: true);
      await repository.savePinMaterial(_pinController.text.trim());
      await repository.save(nextSettings);
      ref.read(securityOrchestratorProvider).enablePinFallback(true);
      ref.read(pinStateControllerProvider.notifier).markPinMaterialReady();
      ref.read(pinStateControllerProvider.notifier).configureEnabled(true);
      if (mounted) {
        if (widget.unlockOnSuccess) {
          ref.read(securityOrchestratorProvider).unlockWithPin();
          final router = GoRouter.maybeOf(context);
          if (router != null) {
            ref.read(appRouterProvider).go('/vault');
          } else {
            Navigator.of(context).pop(true);
          }
        } else {
          ref.invalidate(securitySettingsRepositoryProvider);
          ref.invalidate(securitySettingsControllerProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN 已保存并启用')),
          );
          context.pop();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

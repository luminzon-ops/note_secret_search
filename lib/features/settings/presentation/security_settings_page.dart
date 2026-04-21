import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

class SecuritySettingsPage extends ConsumerWidget {
  const SecuritySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(securitySettingsControllerProvider);
    final pinState = ref.watch(pinStateControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('安全与隐私')),
      body: settingsAsync.when(
        data: (settings) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: settings.biometricPreferred,
                      onChanged: null,
                      title: const Text('优先使用系统生物识别'),
                      subtitle: const Text('当前版本固定启用，后续开放更细粒度设置'),
                    ),
                    SwitchListTile(
                      value: settings.pinEnabled,
                      onChanged: (value) async {
                        if (value && !pinState.hasPinMaterial) {
                          await context.push('/settings/security/pin');
                          return;
                        }
                        await ref.read(securitySettingsControllerProvider.notifier).updatePinEnabled(value);
                      },
                      title: const Text('启用应用 PIN 备用解锁'),
                      subtitle: Text(
                        pinState.hasPinMaterial ? 'PIN 材料已存在，可作为备用入口' : '尚未配置 PIN',
                      ),
                    ),
                    ListTile(
                      title: const Text('设置 / 更新 PIN'),
                      subtitle: const Text('当前为 MVP 骨架，后续会切换到真实 KDF / 安全包裹方案'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/security/pin'),
                    ),
                    ListTile(
                      title: const Text('自动锁定时间'),
                      subtitle: Text('${settings.autoLockSeconds} 秒'),
                      trailing: DropdownButton<int>(
                        value: settings.autoLockSeconds,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          ref.read(securitySettingsControllerProvider.notifier).updateAutoLockSeconds(value);
                        },
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('立即')),
                          DropdownMenuItem(value: 30, child: Text('30 秒')),
                          DropdownMenuItem(value: 60, child: Text('1 分钟')),
                          DropdownMenuItem(value: 300, child: Text('5 分钟')),
                        ],
                      ),
                    ),
                    ListTile(
                      title: const Text('剪贴板清理时间'),
                      subtitle: Text('${settings.clipboardClearSeconds} 秒'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }
}

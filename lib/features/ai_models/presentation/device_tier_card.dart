import 'package:flutter/material.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/device_profiler_bridge.dart';

class DeviceTierCard extends StatelessWidget {
  const DeviceTierCard({super.key, required this.profile});

  final DeviceProfile? profile;

  @override
  Widget build(BuildContext context) {
    final tier = profile?.tier ?? 'low';
    final tierLabel = switch (tier) {
      'high' => '高性能档',
      'mid' => '省电档',
      _ => '最小档',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices, size: 20),
                const SizedBox(width: 8),
                Text('设备能力评级', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Chip(label: Text(tierLabel)),
              ],
            ),
            const SizedBox(height: 12),
            if (profile == null)
              const Text('设备探测暂不可用')
            else ...[
              _ProfileRow('厂商', profile!.manufacturer),
              _ProfileRow('型号', profile!.model),
              _ProfileRow('系统', profile!.osDisplay),
              _ProfileRow('CPU', profile!.cpuDisplay),
              _ProfileRow('内存', '${profile!.ramDisplay} (可用 ${(profile!.availableRamMb / 1024).toStringAsFixed(1)} GB)'),
              _ProfileRow('存储', '${profile!.storageDisplay} (可用 ${(profile!.availableStorageMb / 1024).toStringAsFixed(0)} GB)'),
              const SizedBox(height: 8),
              Text(
                '推荐模型档位：$tierLabel',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

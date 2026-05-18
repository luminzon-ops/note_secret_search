import 'package:flutter/services.dart';

class DeviceProfile {
  const DeviceProfile({
    required this.manufacturer,
    required this.model,
    required this.sdkInt,
    required this.release,
    required this.cpuAbi,
    required this.totalRamMb,
    required this.availableRamMb,
    required this.totalStorageMb,
    required this.availableStorageMb,
    required this.tier,
  });

  final String manufacturer;
  final String model;
  final int sdkInt;
  final String release;
  final String cpuAbi;
  final int totalRamMb;
  final int availableRamMb;
  final int totalStorageMb;
  final int availableStorageMb;
  final String tier; // low / mid / high

  String get ramDisplay =>
      '${(totalRamMb / 1024).toStringAsFixed(1)} GB';
  String get storageDisplay =>
      '${(totalStorageMb / 1024).toStringAsFixed(0)} GB';
  String get osDisplay => 'Android $release (SDK $sdkInt)';
  String get cpuDisplay => cpuAbi;
}

class DeviceProfilerBridge {
  DeviceProfilerBridge({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('note_secret_search/device_profiler');

  final MethodChannel _channel;

  Future<DeviceProfile?> getProfile() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getProfile');
      if (result == null) return null;
      return DeviceProfile(
        manufacturer: result['manufacturer'] as String? ?? 'unknown',
        model: result['model'] as String? ?? 'unknown',
        sdkInt: result['sdkInt'] as int? ?? -1,
        release: result['release'] as String? ?? 'unknown',
        cpuAbi: result['cpuAbi'] as String? ?? 'unknown',
        totalRamMb: result['totalRamMb'] as int? ?? 0,
        availableRamMb: result['availableRamMb'] as int? ?? 0,
        totalStorageMb: result['totalStorageMb'] as int? ?? 0,
        availableStorageMb: result['availableStorageMb'] as int? ?? 0,
        tier: result['tier'] as String? ?? 'low',
      );
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

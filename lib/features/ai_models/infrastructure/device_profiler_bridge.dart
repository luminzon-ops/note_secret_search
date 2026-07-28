import 'package:flutter/services.dart';
import 'package:note_secret_search/features/ai_models/domain/device_profiler.dart';
import 'package:note_secret_search/features/ai_models/domain/model_capability_assessment.dart';

export 'package:note_secret_search/features/ai_models/domain/model_capability_assessment.dart'
    show DeviceProfile;

class DeviceProfilerBridge implements DeviceProfiler {
  DeviceProfilerBridge({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('note_secret_search/device_profiler');

  final MethodChannel _channel;

  @override
  Future<DeviceProfile?> getProfile() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getProfile',
      );
      if (result == null) return null;
      return DeviceProfile.fromPlatformMap(result);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

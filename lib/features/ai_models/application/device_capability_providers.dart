import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/device_profiler.dart';
import 'package:note_secret_search/features/ai_models/domain/model_capability_assessment.dart';

final deviceProfilerBridgeProvider = Provider<DeviceProfiler>((ref) {
  throw StateError(
    'deviceProfilerBridgeProvider must be overridden by app composition',
  );
});

final deviceProfileProvider = FutureProvider<DeviceProfile?>((ref) {
  return ref.watch(deviceProfilerBridgeProvider).getProfile();
});

final deviceCapabilityAssessorProvider = Provider<DeviceCapabilityAssessor>((
  ref,
) {
  return const DeviceCapabilityAssessor();
});

final deviceCapabilityReportProvider = FutureProvider<DeviceCapabilityReport>((
  ref,
) async {
  final catalog = await ref.watch(modelCatalogEntriesProvider.future);
  final profile = await ref.watch(deviceProfileProvider.future);
  return ref
      .watch(deviceCapabilityAssessorProvider)
      .assess(catalog: catalog, profile: profile);
});

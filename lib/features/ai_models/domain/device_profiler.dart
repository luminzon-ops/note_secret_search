import 'package:note_secret_search/features/ai_models/domain/model_capability_assessment.dart';

abstract interface class DeviceProfiler {
  Future<DeviceProfile?> getProfile();
}

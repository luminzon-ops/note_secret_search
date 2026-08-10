import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/domain/model_runtime.dart';

final modelRuntimeCoordinatorProvider = Provider<ModelRuntimeCoordinator>((
  ref,
) {
  throw StateError(
    'modelRuntimeCoordinatorProvider must be overridden by app composition',
  );
});

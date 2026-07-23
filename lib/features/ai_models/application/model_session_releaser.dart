import 'dart:async';

typedef StopModelWrites = void Function();
typedef ReleaseNativeModelSession = Future<void> Function(String modelId);
typedef ConfirmNativeSessionsClosed = Future<void> Function(String modelId);
typedef ModelSessionReleasePredicate = bool Function(String? modelType);

class ModelSessionReleaser {
  ModelSessionReleaser({
    StopModelWrites? stopWrites,
    ReleaseNativeModelSession? releaseEmbedding,
    ReleaseNativeModelSession? releaseLlm,
    ReleaseNativeModelSession? releaseMultimodal,
    ConfirmNativeSessionsClosed? confirmClosed,
    ModelSessionReleasePredicate? shouldReleaseEmbedding,
    ModelSessionReleasePredicate? shouldReleaseLlm,
    ModelSessionReleasePredicate? shouldReleaseMultimodal,
  }) : _stopWrites = stopWrites,
       _releaseEmbedding = releaseEmbedding,
       _releaseLlm = releaseLlm,
       _releaseMultimodal = releaseMultimodal,
       _confirmClosed = confirmClosed,
       _shouldReleaseEmbedding = shouldReleaseEmbedding,
       _shouldReleaseLlm = shouldReleaseLlm,
       _shouldReleaseMultimodal = shouldReleaseMultimodal;

  final StopModelWrites? _stopWrites;
  final ReleaseNativeModelSession? _releaseEmbedding;
  final ReleaseNativeModelSession? _releaseLlm;
  final ReleaseNativeModelSession? _releaseMultimodal;
  final ConfirmNativeSessionsClosed? _confirmClosed;
  final ModelSessionReleasePredicate? _shouldReleaseEmbedding;
  final ModelSessionReleasePredicate? _shouldReleaseLlm;
  final ModelSessionReleasePredicate? _shouldReleaseMultimodal;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  Future<void> releaseForMutation(String modelId, {String? modelType}) {
    if (modelId.trim().isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'Model id is required.');
    }
    final existing = _inFlight[modelId];
    if (existing != null) {
      return existing;
    }

    late final Future<void> operation;
    operation = _release(modelId, modelType: modelType).whenComplete(() {
      if (identical(_inFlight[modelId], operation)) {
        _inFlight.remove(modelId);
      }
    });
    _inFlight[modelId] = operation;
    return operation;
  }

  Future<void> _release(String modelId, {required String? modelType}) async {
    _stopWrites?.call();
    if (_shouldReleaseEmbedding?.call(modelType) ?? true) {
      await _releaseEmbedding?.call(modelId);
    }
    if (_shouldReleaseLlm?.call(modelType) ?? true) {
      await _releaseLlm?.call(modelId);
    }
    if (_shouldReleaseMultimodal?.call(modelType) ?? true) {
      await _releaseMultimodal?.call(modelId);
    }
    await _confirmClosed?.call(modelId);
  }
}

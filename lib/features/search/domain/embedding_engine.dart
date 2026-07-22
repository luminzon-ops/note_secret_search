import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

enum EmbeddingRuntimeStatus {
  notInstalled,
  missing,
  corrupted,
  installedUnverified,
  ready,
  degraded,
}

class EmbeddingRequest {
  const EmbeddingRequest({
    required this.model,
    required this.text,
    this.cancellationToken = EmbeddingCancellationToken.none,
  });

  final ModelRegistryEntry model;
  final String text;
  final EmbeddingCancellationToken cancellationToken;
}

class EmbeddingCancellationToken {
  const EmbeddingCancellationToken._();

  static const none = EmbeddingCancellationToken._();

  bool get isCancelled => false;

  EmbeddingCancellationRegistration register(void Function() listener) {
    return const EmbeddingCancellationRegistration._noop();
  }
}

class EmbeddingCancellationController implements EmbeddingCancellationToken {
  bool _isCancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  @override
  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  @override
  EmbeddingCancellationRegistration register(void Function() listener) {
    if (_isCancelled) {
      listener();
      return const EmbeddingCancellationRegistration._noop();
    }
    _listeners.add(listener);
    return EmbeddingCancellationRegistration._(
      () => _listeners.remove(listener),
    );
  }
}

class EmbeddingCancellationRegistration {
  const EmbeddingCancellationRegistration._noop() : _dispose = null;

  EmbeddingCancellationRegistration._(this._dispose);

  final void Function()? _dispose;

  void dispose() {
    _dispose?.call();
  }
}

abstract interface class EmbeddingCancellationException implements Exception {}

class EmbeddingVector {
  const EmbeddingVector({required this.values, required this.tokenCount});

  final List<double> values;
  final int tokenCount;
}

class EmbeddingEngineState {
  const EmbeddingEngineState({
    required this.ready,
    required this.reason,
    required this.status,
    this.vectorDimension,
    this.modelPath,
    this.checkedAt,
  });

  final bool ready;
  final String reason;
  final EmbeddingRuntimeStatus status;
  final int? vectorDimension;
  final String? modelPath;
  final DateTime? checkedAt;
}

abstract interface class EmbeddingEngine {
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model);

  Future<EmbeddingVector> embed(EmbeddingRequest request);
}

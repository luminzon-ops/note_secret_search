class ModelCatalogTrustException implements Exception {
  const ModelCatalogTrustException(this.code);

  final String code;

  @override
  String toString() => code;
}

enum ModelCatalogKeyStatus { active, overlap, revoked }

class ModelCatalogAcceptanceState {
  const ModelCatalogAcceptanceState({
    required this.catalogVersion,
    required this.payloadDigest,
    required this.keyId,
    this.minimumCatalogVersion = 1,
    this.schemaVersion = 1,
  });

  final int catalogVersion;
  final String payloadDigest;
  final String keyId;
  final int minimumCatalogVersion;
  final int schemaVersion;
}

abstract interface class ModelCatalogAcceptanceStore {
  Future<ModelCatalogAcceptanceState?> read();

  Future<void> accept(ModelCatalogAcceptanceState state);
}

class VerifiedModelCatalog {
  const VerifiedModelCatalog({
    required this.schemaVersion,
    required this.catalogVersion,
    required this.keyId,
    required this.payloadDigest,
    required this.payload,
  });

  final int schemaVersion;
  final int catalogVersion;
  final String keyId;
  final String payloadDigest;
  final Map<String, Object?> payload;
}

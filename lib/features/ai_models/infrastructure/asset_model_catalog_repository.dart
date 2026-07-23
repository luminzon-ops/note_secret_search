import 'package:flutter/services.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_catalog_trust.dart';

class AssetModelCatalogRepository implements ModelCatalogRepository {
  const AssetModelCatalogRepository({
    required AssetBundle assetBundle,
    this.verifier,
    this.acceptanceStore,
  }) : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;
  final ModelCatalogVerifier? verifier;
  final ModelCatalogAcceptanceStore? acceptanceStore;

  static const _catalogAssetPath = 'assets/model_catalog/built_in_catalog.json';

  @override
  Future<List<ModelCatalogEntry>> loadCatalog() async {
    final rawText = await _assetBundle.loadString(_catalogAssetPath);
    final store = acceptanceStore;
    final previous = await store?.read();
    final verified = (verifier ?? ModelCatalogVerifier()).verify(
      rawText,
      minimumCatalogVersionOverride: previous?.minimumCatalogVersion,
      acceptedCatalogVersionOverride: previous?.catalogVersion,
      acceptedPayloadDigestOverride: previous?.payloadDigest,
    );
    final rawModels = verified.payload['models'];
    if (rawModels is! List<Object?>) {
      throw const ModelCatalogTrustException('catalog_payload_invalid');
    }

    final ids = <String>{};
    final entries = <ModelCatalogEntry>[];
    for (final rawModel in rawModels) {
      if (rawModel is! Map<String, Object?>) {
        throw const ModelCatalogTrustException('catalog_model_invalid');
      }
      final entry = ModelCatalogEntry.fromManifestJson(
        rawModel,
        catalogVersion: verified.catalogVersion,
        catalogDigest: verified.payloadDigest,
      );
      if (!ids.add(entry.id)) {
        throw const ModelCatalogTrustException('catalog_model_duplicate');
      }
      // The signed catalog is parsed and validated before this capability gate.
      if (entry.type != 'multimodal_llm') {
        entries.add(entry);
      }
    }
    await store?.accept(
      ModelCatalogAcceptanceState(
        catalogVersion: verified.catalogVersion,
        payloadDigest: verified.payloadDigest,
        keyId: verified.keyId,
        minimumCatalogVersion:
            previous?.minimumCatalogVersion ?? verified.catalogVersion,
      ),
    );
    return List<ModelCatalogEntry>.unmodifiable(entries);
  }
}

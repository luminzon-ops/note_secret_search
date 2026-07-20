import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/domain/search_index_model_revision.dart';

final searchIndexModelRevisionProvider =
    FutureProvider.family<String, ModelRegistryEntry>((ref, model) async {
      final catalogEntries = await ref.watch(
        modelCatalogEntriesProvider.future,
      );
      final catalog = catalogEntries
          .where((entry) => entry.id == model.id)
          .firstOrNull;
      final tokenizer = catalog?.tokenizer;
      if (catalog == null || tokenizer == null || catalog.runtime == null) {
        throw StateError('Embedding model catalog metadata is unavailable.');
      }
      final asset = await rootBundle.load(tokenizer.assetPath);
      final digest = sha256
          .convert(
            Uint8List.sublistView(
              asset,
              asset.offsetInBytes,
              asset.offsetInBytes + asset.lengthInBytes,
            ),
          )
          .toString();
      return resolveSearchIndexModelRevision(
        model: model,
        catalog: catalog,
        tokenizerAssetSha256: digest,
      );
    });

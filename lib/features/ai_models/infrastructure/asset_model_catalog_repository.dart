import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_repository.dart';

class AssetModelCatalogRepository implements ModelCatalogRepository {
  const AssetModelCatalogRepository({required AssetBundle assetBundle})
      : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;

  static const _catalogAssetPath = 'assets/model_catalog/built_in_catalog.json';

  @override
  Future<List<ModelCatalogEntry>> loadCatalog() async {
    final rawText = await _assetBundle.loadString(_catalogAssetPath);
    final decoded = jsonDecode(rawText);
    if (decoded is! List) {
      return const <ModelCatalogEntry>[];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ModelCatalogEntry.fromJson)
        .toList(growable: false);
  }
}

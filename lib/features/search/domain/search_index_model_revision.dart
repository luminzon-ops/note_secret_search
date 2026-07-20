import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

String resolveSearchIndexModelRevision({
  required ModelRegistryEntry model,
  required ModelCatalogEntry catalog,
  required String tokenizerAssetSha256,
}) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(tokenizerAssetSha256)) {
    throw ArgumentError.value(
      tokenizerAssetSha256,
      'tokenizerAssetSha256',
      'Must be a lowercase SHA-256 hex digest.',
    );
  }
  final artifacts = model.artifacts.toList(growable: false)
    ..sort((left, right) {
      final role = left.role.compareTo(right.role);
      return role != 0 ? role : left.sourceId.compareTo(right.sourceId);
    });
  final tokenizer = catalog.tokenizer;
  final runtime = catalog.runtime;
  final canonical = <Object?>[
    'note-secret-search/model-revision/v1',
    model.id,
    model.type,
    model.provider,
    model.version ?? '',
    model.quantization ?? '',
    model.checksum ?? '',
    model.integrityStatus.name,
    <Object?>[
      for (final artifact in artifacts)
        <Object?>[artifact.role, artifact.sourceId, artifact.checksum ?? ''],
    ],
    <Object?>[
      tokenizer?.format ?? '',
      tokenizer?.maxSequenceLength ?? 0,
      tokenizer?.lowercase ?? false,
      tokenizerAssetSha256,
    ],
    <Object?>[
      runtime?.inputIdsName ?? '',
      runtime?.attentionMaskName ?? '',
      runtime?.tokenTypeIdsName ?? '',
      runtime?.outputName ?? '',
      runtime?.pooling ?? '',
      runtime?.normalization ?? '',
    ],
  ];
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

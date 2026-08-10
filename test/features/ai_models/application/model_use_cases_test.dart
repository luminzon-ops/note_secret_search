import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/application/model_use_cases.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

const _entry = ModelCatalogEntry(
  id: 'model-1',
  type: 'embedding',
  tier: 'mvp',
  displayName: 'Model',
  description: 'Fixture',
  sizeBytes: 10,
  minRamMb: 512,
  recommendedTier: 'mvp',
  sources: <ModelSourceEntry>[_source],
);

const _source = ModelSourceEntry(
  id: 'source-1',
  label: 'Source',
  url: 'https://example.com/model.onnx',
);

void main() {
  test('model maintenance use case delegates every model command', () async {
    final calls = <String>[];
    final useCase = ModelMaintenanceUseCase(
      startDownload: ({required entry, required source}) async {
        calls.add('start:${entry.id}:${source.id}');
      },
      pause: (modelId, {required sourceId}) async {
        calls.add('pause:$modelId:$sourceId');
      },
      delete: (modelId) async {
        calls.add('delete:$modelId');
      },
      revalidate: (modelId) async {
        calls.add('revalidate:$modelId');
      },
      repair: (modelId) async {
        calls.add('repair:$modelId');
      },
      markFailed: (modelId, {required sourceId, required message}) async {
        calls.add('failed:$modelId:$sourceId:$message');
      },
    );

    await useCase.start(entry: _entry, source: _source);
    await useCase.pause('model-1', sourceId: 'source-1');
    await useCase.delete('model-1');
    await useCase.revalidate('model-1');
    await useCase.repair('model-1');
    await useCase.markFailed(
      'model-1',
      sourceId: 'source-1',
      message: 'manual failure',
    );

    expect(calls, <String>[
      'start:model-1:source-1',
      'pause:model-1:source-1',
      'delete:model-1',
      'revalidate:model-1',
      'repair:model-1',
      'failed:model-1:source-1:manual failure',
    ]);
  });

  test('model activation use case delegates embedding and local LLM', () async {
    final calls = <String>[];
    final useCase = ModelActivationUseCase(
      setEmbedding: (modelId) async {
        calls.add('embedding:${modelId ?? 'none'}');
      },
      setLocalLlm: (modelId) async {
        calls.add('llm:${modelId ?? 'none'}');
      },
    );

    await useCase.setEmbedding('embedding-1');
    await useCase.setEmbedding(null);
    await useCase.setLocalLlm('llm-1');
    await useCase.setLocalLlm(null);

    expect(calls, <String>[
      'embedding:embedding-1',
      'embedding:none',
      'llm:llm-1',
      'llm:none',
    ]);
  });
}

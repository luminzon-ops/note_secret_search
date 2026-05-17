import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_presentation_formatter.dart';

void main() {
  test('formatModelCapabilitySummary shows all supported metadata in the approved order', () {
    const model = ModelRegistryEntry(
      id: 'embed-1',
      type: 'embedding',
      provider: 'builtin',
      name: 'MiniLM Embedding',
      version: '1.0.2',
      sizeBytes: 10485760,
      quantization: 'Q8',
      minRamMb: 512,
      recommendedTier: 'mvp',
      localPath: '/data/models/minilm.onnx',
      checksum: 'abc',
      enabled: true,
      installedAt: null,
      filePresent: true,
    );

    expect(
      formatModelCapabilitySummary(model),
      'builtin · embedding · Q8 · 版本 1.0.2 · 10.0 MB · RAM ≥ 512MB · 推荐档位 mvp',
    );
  });

  test('formatModelCapabilitySummary omits absent metadata', () {
    const model = ModelRegistryEntry(
      id: 'embed-1',
      type: 'embedding',
      provider: 'builtin',
      name: 'MiniLM Embedding',
      version: null,
      sizeBytes: null,
      quantization: null,
      minRamMb: null,
      recommendedTier: null,
      localPath: '/data/models/minilm.onnx',
      checksum: 'abc',
      enabled: true,
      installedAt: null,
      filePresent: true,
    );

    expect(formatModelCapabilitySummary(model), 'builtin · embedding');
  });

  test('formatSearchSettingsDeploymentStatus returns ready wording for installed model', () {
    const model = ModelRegistryEntry(
      id: 'embed-1',
      type: 'embedding',
      provider: 'builtin',
      name: 'MiniLM Embedding',
      version: '1.0.2',
      sizeBytes: 10485760,
      quantization: 'Q8',
      minRamMb: 512,
      recommendedTier: 'mvp',
      localPath: '/data/models/minilm.onnx',
      checksum: 'abc',
      enabled: true,
      installedAt: null,
      filePresent: true,
    );

    expect(
      formatSearchSettingsDeploymentStatus(model),
      '部署状态：本地文件已就绪，可用于当前语义检索。',
    );
  });

  test('formatSearchSettingsDeploymentStatus returns degraded wording for missing-file model', () {
    const model = ModelRegistryEntry(
      id: 'embed-1',
      type: 'embedding',
      provider: 'builtin',
      name: 'MiniLM Embedding',
      version: '1.0.2',
      sizeBytes: 10485760,
      quantization: 'Q8',
      minRamMb: 512,
      recommendedTier: 'mvp',
      localPath: '/data/models/minilm.onnx',
      checksum: 'abc',
      enabled: true,
      installedAt: null,
      filePresent: false,
    );

    expect(
      formatSearchSettingsDeploymentStatus(model),
      '部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。',
    );
  });

  test('formatInstalledModelDeploymentStatus returns ready wording for installed model', () {
    const model = ModelRegistryEntry(
      id: 'embed-1',
      type: 'embedding',
      provider: 'builtin',
      name: 'MiniLM Embedding',
      version: '1.0.2',
      sizeBytes: 10485760,
      quantization: 'Q8',
      minRamMb: 512,
      recommendedTier: 'mvp',
      localPath: '/data/models/minilm.onnx',
      checksum: 'abc',
      enabled: true,
      installedAt: null,
      filePresent: true,
    );

    expect(formatInstalledModelDeploymentStatus(model), '部署状态：本地已就绪。');
  });

  test('formatInstalledModelDeploymentStatus returns degraded wording for missing-file model', () {
    const model = ModelRegistryEntry(
      id: 'embed-1',
      type: 'embedding',
      provider: 'builtin',
      name: 'MiniLM Embedding',
      version: '1.0.2',
      sizeBytes: 10485760,
      quantization: 'Q8',
      minRamMb: 512,
      recommendedTier: 'mvp',
      localPath: '/data/models/minilm.onnx',
      checksum: 'abc',
      enabled: true,
      installedAt: null,
      filePresent: false,
    );

    expect(
      formatInstalledModelDeploymentStatus(model),
      '部署状态：本地文件缺失，当前记录不可直接使用。',
    );
  });

  test('formatCatalogDeploymentStatus returns not-downloaded wording for null entry', () {
    expect(formatCatalogDeploymentStatus(null), '部署状态：尚未下载到本地。');
  });

  test('formatCatalogDeploymentStatus returns ready wording for installed entry', () {
    const model = ModelRegistryEntry(
      id: 'embed-1',
      type: 'embedding',
      provider: 'builtin',
      name: 'MiniLM Embedding',
      version: '1.0.2',
      sizeBytes: 10485760,
      quantization: 'Q8',
      minRamMb: 512,
      recommendedTier: 'mvp',
      localPath: '/data/models/minilm.onnx',
      checksum: 'abc',
      enabled: true,
      installedAt: null,
      filePresent: true,
    );

    expect(
      formatCatalogDeploymentStatus(model),
      '部署状态：本地已就绪，可用于后续启用或检索配置。',
    );
  });

  test('formatCatalogDeploymentStatus returns degraded wording for missing-file entry', () {
    const model = ModelRegistryEntry(
      id: 'embed-1',
      type: 'embedding',
      provider: 'builtin',
      name: 'MiniLM Embedding',
      version: '1.0.2',
      sizeBytes: 10485760,
      quantization: 'Q8',
      minRamMb: 512,
      recommendedTier: 'mvp',
      localPath: '/data/models/minilm.onnx',
      checksum: 'abc',
      enabled: true,
      installedAt: null,
      filePresent: false,
    );

    expect(
      formatCatalogDeploymentStatus(model),
      '部署状态：本地记录存在，但文件缺失，需要重新下载。',
    );
  });

  test('formatCatalogRuntimeSupportStatus explains deployable multimodal entries', () {
    const entry = ModelCatalogEntry(
      id: 'minicpm_v_4_6_q4_k_m',
      type: 'multimodal_llm',
      tier: 'local_multimodal',
      displayName: 'MiniCPM-V 4.6 Q4_K_M Multimodal',
      description: 'Requires LLM GGUF plus mmproj-model-f16.gguf.',
      sizeBytes: 1516275776,
      minRamMb: 6144,
      recommendedTier: 'vision_language_local',
      sources: <ModelSourceEntry>[],
    );

    expect(isCatalogEntryDownloadSupported(entry), isTrue);
    expect(
      formatCatalogRuntimeSupportStatus(entry),
      '运行时支持：需要下载主模型和视觉投影文件，部署后可进行本地多模态推理。',
    );
  });

  group('shouldShowGenericTrustExplainer', () {
    test('returns false for a single signed source entry', () {
      const sources = [
        ModelSourceEntry(
          id: 'signed-only',
          label: 'Signed Only Source',
          url: 'https://example.com/signed.onnx',
          checksum: 'sha256:signed',
          signature: 'base64:sig',
          signatureAlgorithm: 'RSA-SHA256',
          keyId: 'key-1',
        ),
      ];

      expect(shouldShowGenericTrustExplainer(sources), isFalse);
    });

    test('returns true for a mixed-source entry with signed metadata', () {
      const sources = [
        ModelSourceEntry(
          id: 'signed-src',
          label: 'Signed Source',
          url: 'https://example.com/signed.onnx',
          checksum: 'sha256:signed',
          signature: 'base64:sig',
          signatureAlgorithm: 'RSA-SHA256',
          keyId: 'key-1',
        ),
        ModelSourceEntry(
          id: 'unsigned-src',
          label: 'Unsigned Source',
          url: 'https://example.com/unsigned.onnx',
          checksum: 'sha256:unsigned',
        ),
      ];

      expect(shouldShowGenericTrustExplainer(sources), isTrue);
    });

    test('returns false when no source declares artifact trust', () {
      const sources = [
        ModelSourceEntry(
          id: 'unsigned-src',
          label: 'Unsigned Source',
          url: 'https://example.com/unsigned.onnx',
          checksum: 'sha256:unsigned',
        ),
      ];

      expect(shouldShowGenericTrustExplainer(sources), isFalse);
    });
  });
}

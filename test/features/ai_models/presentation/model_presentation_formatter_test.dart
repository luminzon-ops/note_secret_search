import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_presentation_formatter.dart';

const _installedModelDigest =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _installedModel = ModelRegistryEntry(
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
  checksum: _installedModelDigest,
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
  releaseId: 'release-1',
  catalogVersion: 1,
  catalogDigest:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  generation: 1,
  revisionRoot: 'revisions/1',
  artifacts: <ModelArtifactPath>[
    ModelArtifactPath(
      artifactId: 'model',
      releaseId: 'release-1',
      role: 'model',
      sourceId: 'test-source',
      localPath: '/data/models/minilm.onnx',
      relativePath: 'runtime/model.onnx',
      expectedChecksum: _installedModelDigest,
      verifiedChecksum: _installedModelDigest,
      expectedSizeBytes: 10485760,
      verifiedSizeBytes: 10485760,
      state: 'installed',
      verifiedAt: 1,
    ),
  ],
);

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
    expect(
      formatSearchSettingsDeploymentStatus(_installedModel),
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
    expect(
      formatInstalledModelDeploymentStatus(_installedModel),
      '部署状态：本地已就绪。',
    );
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
    expect(
      formatCatalogDeploymentStatus(_installedModel),
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

  test('formatCatalogRuntimeSupportStatus rejects unavailable multimodal entries', () {
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

    expect(isCatalogEntryDownloadSupported(entry), isFalse);
    expect(
      formatCatalogRuntimeSupportStatus(entry),
      '运行时支持：当前版本尚不支持 multimodal_llm；需要专用 runtime 后才能下载部署。',
    );
  });

  group('signature metadata trust UI suppression', () {
    const signedSource = ModelSourceEntry(
      id: 'signed-src',
      label: 'Signed Source',
      url: 'https://example.com/signed.onnx',
      checksum: 'sha256:signed',
      signature: 'base64:sig',
      signatureAlgorithm: 'RSA-SHA256',
      keyId: 'key-1',
    );
    const unsignedSource = ModelSourceEntry(
      id: 'unsigned-src',
      label: 'Unsigned Source',
      url: 'https://example.com/unsigned.onnx',
      checksum: 'sha256:unsigned',
    );

    test('keeps source labels plain', () {
      expect(formatSourceLabelWithTrust(signedSource), 'Signed Source');
    });

    test('omits local and generic trust captions', () {
      expect(formatEffectiveSourceTrustCaption(signedSource), isNull);
      expect(
        formatGenericTrustExplainer(const <ModelSourceEntry>[signedSource, unsignedSource]),
        isNull,
      );
      expect(
        shouldShowGenericTrustExplainer(const <ModelSourceEntry>[signedSource, unsignedSource]),
        isFalse,
      );
    });
  });
}

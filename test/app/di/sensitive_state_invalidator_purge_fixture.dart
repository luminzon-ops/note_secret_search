part of 'sensitive_state_invalidator_provider_test.dart';

const _fixtureCatalogDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _embeddingDigest =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _llmDigest =
    'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

const _embeddingModel = ModelRegistryEntry(
  id: 'embedding-sensitive',
  type: 'embedding',
  provider: 'test',
  name: 'Sensitive embedding',
  version: '1',
  sizeBytes: 1024,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'test',
  localPath: '/private/models/embedding.onnx',
  checksum: null,
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
  releaseId: 'release-1',
  catalogVersion: 7,
  catalogDigest: _fixtureCatalogDigest,
  generation: 1,
  revisionRoot: 'revisions/1',
  artifacts: <ModelArtifactPath>[
    ModelArtifactPath(
      artifactId: 'model',
      releaseId: 'release-1',
      role: 'model',
      sourceId: 'embedding-source',
      localPath: '/private/models/embedding.onnx',
      relativePath: 'runtime/embedding.onnx',
      expectedChecksum: _embeddingDigest,
      verifiedChecksum: _embeddingDigest,
      expectedSizeBytes: 1024,
      verifiedSizeBytes: 1024,
      state: 'installed',
      verifiedAt: 1,
    ),
  ],
);

const _llmModel = ModelRegistryEntry(
  id: 'llm-sensitive',
  type: 'llm',
  provider: 'test',
  name: 'Sensitive LLM',
  version: '1',
  sizeBytes: 2048,
  quantization: 'Q4',
  minRamMb: 512,
  recommendedTier: 'test',
  localPath: '/private/models/llm.gguf',
  checksum: null,
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
  releaseId: 'release-1',
  catalogVersion: 7,
  catalogDigest: _fixtureCatalogDigest,
  generation: 1,
  revisionRoot: 'revisions/1',
  artifacts: <ModelArtifactPath>[
    ModelArtifactPath(
      artifactId: 'model',
      releaseId: 'release-1',
      role: 'model',
      sourceId: 'llm-source',
      localPath: '/private/models/llm.gguf',
      relativePath: 'runtime/llm.gguf',
      expectedChecksum: _llmDigest,
      verifiedChecksum: _llmDigest,
      expectedSizeBytes: 2048,
      verifiedSizeBytes: 2048,
      state: 'installed',
      verifiedAt: 1,
    ),
  ],
);

const _externalConfig = ExternalProviderConfig(
  id: 'external-sensitive',
  providerType: ExternalProviderType.ollama,
  displayName: 'Private Ollama',
  baseUrl: 'https://private-provider.example',
  apiKey: 'runtime-secret-key',
  modelName: 'private-model',
  embeddingModelName: 'private-embedding',
  enabled: true,
  allowSensitiveFields: true,
);

part of 'model_management_page_test.dart';

void _registerTrustStatusCopyCases() {
  testWidgets(
    'catalog entry omits trust explainer when signature metadata is present',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'trust-model-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Signed Embedding Model',
                  description: 'A model with artifact trust declaration.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'trust-source-1',
                      label: 'Signed Source',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed123',
                      signature: 'base64:signedsig==',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'signer-key-1',
                    ),
                    ModelSourceEntry(
                      id: 'unsigned-source-2',
                      label: 'Unsigned Source',
                      url: 'https://example.com/unsigned.onnx',
                      checksum: 'sha256:unsigned123',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => const <ModelDownloadTask>[],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('已签名'), findsNothing);
    },
  );

  testWidgets(
    'ModelManagementPage shows plain source label in status card despite signature metadata',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'trust-model-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Signed Embedding Model',
                  description: 'A model with artifact trust declaration.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'signed-source-1',
                      label: 'Signed Mirror',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed123',
                      signature: 'base64:signedsig==',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'signer-key-1',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-1',
                  modelId: 'trust-model-1',
                  sourceId: 'signed-source-1',
                  status: ModelDownloadStatus.downloading,
                  totalBytes: 10485760,
                  downloadedBytes: 5242880,
                  averageSpeed: 1572864,
                  errorMessage: null,
                  resumable: true,
                  createdAt: DateTime(2026, 4, 21, 10, 0),
                  updatedAt: DateTime(2026, 4, 21, 10, 1, 30),
                ),
              ],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前来源：Signed Mirror'), findsOneWidget);
      expect(find.textContaining('已签名'), findsNothing);
    },
  );

  testWidgets(
    'ModelManagementPage shows plain source label in status card for unsigned source',
    (tester) async {
      // Unsigned sources should NOT show trust suffix in status card
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'unsigned-model-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Unsigned Embedding Model',
                  description: 'A model without artifact trust.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'unsigned-source-1',
                      label: 'Unsigned Mirror',
                      url: 'https://example.com/unsigned.onnx',
                      checksum: 'sha256:unsigned123',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-1',
                  modelId: 'unsigned-model-1',
                  sourceId: 'unsigned-source-1',
                  status: ModelDownloadStatus.downloading,
                  totalBytes: 10485760,
                  downloadedBytes: 5242880,
                  averageSpeed: 1572864,
                  errorMessage: null,
                  resumable: true,
                  createdAt: DateTime(2026, 4, 21, 10, 0),
                  updatedAt: DateTime(2026, 4, 21, 10, 1, 30),
                ),
              ],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      // The status card source label for unsigned source should NOT include trust suffix
      expect(find.text('当前来源：Unsigned Mirror'), findsOneWidget);
      expect(find.textContaining('当前来源：Unsigned Mirror (已签名)'), findsNothing);
    },
  );
}

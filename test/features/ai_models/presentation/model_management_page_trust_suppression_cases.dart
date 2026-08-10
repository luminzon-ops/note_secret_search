part of 'model_management_page_test.dart';

void _registerTrustSuppressionCases() {
  group('signature metadata trust UI suppression', () {
    testWidgets(
      'omits local trust caption when effective source has signature metadata',
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
                    displayName: 'Signed Model',
                    description: 'Model with signed source.',
                    sizeBytes: 10485760,
                    minRamMb: 512,
                    recommendedTier: 'mvp',
                    sources: <ModelSourceEntry>[
                      ModelSourceEntry(
                        id: 'signed-src',
                        label: 'Signed Mirror',
                        url: 'https://example.com/signed.onnx',
                        checksum: 'sha256:signed',
                        signature: 'base64:sig',
                        signatureAlgorithm: 'RSA-SHA256',
                        keyId: 'key-1',
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

    testWidgets('omits local trust caption when effective source is unsigned', (
      tester,
    ) async {
      // When the current/effective source does NOT declare artifact trust,
      // no local trust caption should appear below the source selector.
      // The generic explainer (if any) explains trust for other sources.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'unsigned-model-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Unsigned Model',
                  description: 'Model with unsigned source.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'unsigned-src',
                      label: 'Plain Mirror',
                      url: 'https://example.com/unsigned.onnx',
                      checksum: 'sha256:unsigned',
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

      // The local trust caption should NOT appear for unsigned source
      expect(find.text('已签名来源声明'), findsNothing);
    });

    testWidgets(
      'omits all trust captions for mixed sources with signature metadata',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              modelCatalogEntriesProvider.overrideWith(
                (ref) async => const [
                  ModelCatalogEntry(
                    id: 'mixed-model',
                    type: 'embedding',
                    tier: 'mvp',
                    displayName: 'Mixed Trust Model',
                    description: 'Model with mixed sources.',
                    sizeBytes: 10485760,
                    minRamMb: 512,
                    recommendedTier: 'mvp',
                    sources: <ModelSourceEntry>[
                      ModelSourceEntry(
                        id: 'signed-src',
                        label: 'Signed Mirror',
                        url: 'https://example.com/signed.onnx',
                        checksum: 'sha256:signed',
                        signature: 'base64:sig',
                        signatureAlgorithm: 'RSA-SHA256',
                        keyId: 'key-1',
                      ),
                      ModelSourceEntry(
                        id: 'unsigned-src',
                        label: 'Unsigned Mirror',
                        url: 'https://example.com/unsigned.onnx',
                        checksum: 'sha256:unsigned',
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
  });

  group('signature metadata never produces trust captions', () {
    testWidgets(
      '(a) single source with signature metadata shows no trust caption',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              modelCatalogEntriesProvider.overrideWith(
                (ref) async => const [
                  ModelCatalogEntry(
                    id: 'single-signed-model',
                    type: 'embedding',
                    tier: 'mvp',
                    displayName: 'Single Signed Model',
                    description: 'Model with one signed source.',
                    sizeBytes: 10485760,
                    minRamMb: 512,
                    recommendedTier: 'mvp',
                    sources: <ModelSourceEntry>[
                      ModelSourceEntry(
                        id: 'single-signed-src',
                        label: 'Signed Only Source',
                        url: 'https://example.com/signed.onnx',
                        checksum: 'sha256:signed',
                        signature: 'base64:sig',
                        signatureAlgorithm: 'RSA-SHA256',
                        keyId: 'key-1',
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
      '(b) multiple sources with signature metadata show no trust explainer',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              modelCatalogEntriesProvider.overrideWith(
                (ref) async => const [
                  ModelCatalogEntry(
                    id: 'multi-source-model',
                    type: 'embedding',
                    tier: 'mvp',
                    displayName: 'Multi Source Model',
                    description: 'Model with multiple sources.',
                    sizeBytes: 10485760,
                    minRamMb: 512,
                    recommendedTier: 'mvp',
                    sources: <ModelSourceEntry>[
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
      '(c) effective source with signature metadata shows no trust text',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              modelCatalogEntriesProvider.overrideWith(
                (ref) async => const [
                  ModelCatalogEntry(
                    id: 'mixed-model',
                    type: 'embedding',
                    tier: 'mvp',
                    displayName: 'Mixed Trust Model',
                    description: 'Model with mixed sources.',
                    sizeBytes: 10485760,
                    minRamMb: 512,
                    recommendedTier: 'mvp',
                    sources: <ModelSourceEntry>[
                      ModelSourceEntry(
                        id: 'signed-src',
                        label: 'Signed Mirror',
                        url: 'https://example.com/signed.onnx',
                        checksum: 'sha256:signed',
                        signature: 'base64:sig',
                        signatureAlgorithm: 'RSA-SHA256',
                        keyId: 'key-1',
                      ),
                      ModelSourceEntry(
                        id: 'unsigned-src',
                        label: 'Unsigned Mirror',
                        url: 'https://example.com/unsigned.onnx',
                        checksum: 'sha256:unsigned',
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
      '(d) signature metadata on another source produces no trust text',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              modelCatalogEntriesProvider.overrideWith(
                (ref) async => const [
                  ModelCatalogEntry(
                    id: 'mixed-model',
                    type: 'embedding',
                    tier: 'mvp',
                    displayName: 'Mixed Trust Model',
                    description: 'Model with mixed sources.',
                    sizeBytes: 10485760,
                    minRamMb: 512,
                    recommendedTier: 'mvp',
                    sources: <ModelSourceEntry>[
                      ModelSourceEntry(
                        id: 'unsigned-src',
                        label: 'Unsigned Mirror',
                        url: 'https://example.com/unsigned.onnx',
                        checksum: 'sha256:unsigned',
                      ),
                      ModelSourceEntry(
                        id: 'signed-src',
                        label: 'Signed Mirror',
                        url: 'https://example.com/signed.onnx',
                        checksum: 'sha256:signed',
                        signature: 'base64:sig',
                        signatureAlgorithm: 'RSA-SHA256',
                        keyId: 'key-1',
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
  });
}

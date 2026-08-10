part of 'model_management_page_test.dart';

void _registerTrustCopyCases() {
  testWidgets(
    'catalog source list keeps plain labels when signature metadata is present',
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
                      id: 'trust-source-2',
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

      // Verify the 推荐来源 section renders
      expect(find.text('推荐来源'), findsOneWidget);

      expect(find.text('Signed Source'), findsWidgets);
      expect(find.text('Unsigned Source'), findsWidgets);
      expect(find.textContaining('已签名'), findsNothing);
    },
  );

  testWidgets(
    'current-source text stays plain when signature metadata is present',
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

      expect(find.text('Signed Source'), findsAtLeast(2));
      expect(find.textContaining('已签名'), findsNothing);
    },
  );

  testWidgets('current-source text shows no trust suffix for unsigned source', (
    tester,
  ) async {
    // Unsigned sources should NOT show trust hint in selector/current-source text
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
                description: 'A model without artifact trust declaration.',
                sizeBytes: 10485760,
                minRamMb: 512,
                recommendedTier: 'mvp',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'unsigned-source-1',
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

    // The section header "当前下载源" appears.
    expect(find.text('当前下载源'), findsOneWidget);
    // Source label text (no trust suffix) appears.
    expect(find.text('Unsigned Source'), findsAtLeast(1));
    // It should NOT include trust indicator (已签名) anywhere.
    expect(find.textContaining('已签名'), findsNothing);
  });

  testWidgets(
    'dropdown items never show trust suffixes from signature metadata',
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
                      id: 'signed-source',
                      label: 'Signed Source',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed123',
                      signature: 'base64:signedsig==',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'signer-key-1',
                    ),
                    ModelSourceEntry(
                      id: 'unsigned-source',
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

      // Open dropdown
      final dropdownFinder = find.byType(DropdownButton<String>);
      await scrollUntilFound(tester, dropdownFinder);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      expect(find.text('Signed Source'), findsWidgets);
      expect(find.text('Unsigned Source'), findsWidgets);
      expect(find.textContaining('已签名'), findsNothing);
    },
  );
}

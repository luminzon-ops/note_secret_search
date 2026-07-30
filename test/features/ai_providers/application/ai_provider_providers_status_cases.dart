part of 'ai_provider_providers_test.dart';

void _runAiProviderStatusCases() {
  test('enabledExternalProviderProvider returns the enabled config', () async {
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );

    addTearDown(container.dispose);

    final config = await container.read(enabledExternalProviderProvider.future);
    expect(config?.id, 'provider-1');
    expect(config?.baseUrl, 'https://example.com/v1');
  });

  test(
    'externalProviderStatusProvider reports provider ready when config exists',
    () async {
      final repository = _MemoryExternalProviderRepository(
        configs: const [_provider],
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderRepositoryProvider.overrideWithValue(repository),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults().copyWith(
              allowExternalProviderAccess: true,
            ),
          ),
        ],
      );

      addTearDown(container.dispose);

      final status = await container.read(
        externalProviderStatusProvider.future,
      );
      expect(status.available, isTrue);
      expect(status.reason, contains('OpenAI 兼容服务'));
      expect(status.config?.modelName, 'gpt-4.1-mini');
    },
  );

  test(
    'externalProviderStatusProvider reports unavailable when no config exists',
    () async {
      final repository = _MemoryExternalProviderRepository();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderRepositoryProvider.overrideWithValue(repository),
        ],
      );

      addTearDown(container.dispose);

      final status = await container.read(
        externalProviderStatusProvider.future,
      );
      expect(status.available, isFalse);
      expect(status.config, isNull);
    },
  );

  test(
    'externalProviderStatusProvider reports unavailable before global opt-in',
    () async {
      final repository = _MemoryExternalProviderRepository(
        configs: const [_provider],
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderRepositoryProvider.overrideWithValue(repository),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
        ],
      );

      addTearDown(container.dispose);

      final status = await container.read(
        externalProviderStatusProvider.future,
      );
      expect(status.available, isFalse);
      expect(status.reason, contains('尚未允许外部 AI 访问'));
      expect(status.config?.id, _provider.id);
    },
  );
}

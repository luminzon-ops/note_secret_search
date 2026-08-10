part of 'ai_provider_providers_test.dart';

void _runAiProviderSettingsCases() {
  test(
    'externalProviderSettingsController revokes old consent when saving config',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = _MemoryExternalProviderRepository(
        configs: const [_provider],
      );
      final client = _RecordingExternalProviderClient();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderConsentStoreProvider.overrideWith(
            (ref) => const _SharedPreferencesConsentStore(),
          ),
          externalProviderRepositoryProvider.overrideWithValue(repository),
          externalProviderClientRouterProvider.overrideWithValue(client),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(
        externalProviderSettingsControllerProvider,
      );
      final confirmation = container.read(
        externalPrivacyConfirmationControllerProvider,
      );
      final updated = _provider.copyWith(modelName: 'gpt-4.1');

      await confirmation.markAcknowledged(
        _provider,
        includesPrivateContext: true,
      );
      expect(
        await confirmation.hasAcknowledged(
          _provider,
          includesPrivateContext: true,
        ),
        isTrue,
      );

      await controller.save(updated);
      await controller.testConnection(updated);

      expect(repository.saved.single.id, 'provider-1');
      expect(
        await confirmation.hasAcknowledged(
          _provider,
          includesPrivateContext: true,
        ),
        isFalse,
      );
      expect(
        await confirmation.hasAcknowledged(
          updated,
          includesPrivateContext: true,
        ),
        isFalse,
      );
      expect(client.lastTested?.baseUrl, 'https://example.com/v1');
    },
  );

  test('display metadata changes preserve both consent scopes', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        externalProviderConsentStoreProvider.overrideWith(
          (ref) => const _SharedPreferencesConsentStore(),
        ),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final confirmation = container.read(
      externalPrivacyConfirmationControllerProvider,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: false,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: true,
    );

    final renamed = _provider.copyWith(displayName: 'Renamed provider');
    await container
        .read(externalProviderSettingsControllerProvider)
        .save(renamed);

    expect(
      await confirmation.hasAcknowledged(
        renamed,
        includesPrivateContext: false,
      ),
      isTrue,
    );
    expect(
      await confirmation.hasAcknowledged(renamed, includesPrivateContext: true),
      isTrue,
    );
  });

  test('private policy changes revoke only private consent', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        externalProviderConsentStoreProvider.overrideWith(
          (ref) => const _SharedPreferencesConsentStore(),
        ),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final confirmation = container.read(
      externalPrivacyConfirmationControllerProvider,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: false,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: true,
    );

    final changed = _provider.copyWith(allowSensitiveFields: true);
    await container
        .read(externalProviderSettingsControllerProvider)
        .save(changed);

    expect(
      await confirmation.hasAcknowledged(
        changed,
        includesPrivateContext: false,
      ),
      isTrue,
    );
    expect(
      await confirmation.hasAcknowledged(changed, includesPrivateContext: true),
      isFalse,
    );
  });

  test('explicit revoke clears both consent scopes', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        externalProviderConsentStoreProvider.overrideWith(
          (ref) => const _SharedPreferencesConsentStore(),
        ),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final confirmation = container.read(
      externalPrivacyConfirmationControllerProvider,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: false,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: true,
    );

    await container
        .read(externalProviderSettingsControllerProvider)
        .revokeConsent(_provider);

    expect(
      await confirmation.hasAcknowledged(
        _provider,
        includesPrivateContext: false,
      ),
      isFalse,
    );
    expect(
      await confirmation.hasAcknowledged(
        _provider,
        includesPrivateContext: true,
      ),
      isFalse,
    );
  });

  test(
    'explicit revoke reloads the persisted fingerprint by config id',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = _MemoryExternalProviderRepository(
        configs: const [_provider],
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderConsentStoreProvider.overrideWith(
            (ref) => const _SharedPreferencesConsentStore(),
          ),
          externalProviderRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final confirmation = container.read(
        externalPrivacyConfirmationControllerProvider,
      );
      await confirmation.markAcknowledged(
        _provider,
        includesPrivateContext: false,
      );
      await confirmation.markAcknowledged(
        _provider,
        includesPrivateContext: true,
      );

      await container
          .read(externalProviderSettingsControllerProvider)
          .revokeConsent(
            _provider.copyWith(
              providerType: ExternalProviderType.ollama,
              baseUrl: 'http://localhost:11434',
              apiKey: '',
              modelName: 'unsaved-model',
            ),
          );

      expect(
        await confirmation.hasAcknowledged(
          _provider,
          includesPrivateContext: false,
        ),
        isFalse,
      );
      expect(
        await confirmation.hasAcknowledged(
          _provider,
          includesPrivateContext: true,
        ),
        isFalse,
      );
    },
  );
}

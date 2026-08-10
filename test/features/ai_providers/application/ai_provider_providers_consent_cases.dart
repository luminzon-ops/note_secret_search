part of 'ai_provider_providers_test.dart';

void _runAiProviderConsentCases() {
  test(
    'external provider consent fingerprint canonicalizes endpoint and ignores display metadata',
    () {
      final equivalent = _provider.copyWith(
        displayName: 'Renamed',
        baseUrl: ' HTTPS://EXAMPLE.COM/v1/// ',
        updatedAt: DateTime(2026, 7, 22),
      );

      expect(
        normalizeExternalProviderEndpoint(equivalent.baseUrl),
        'https://example.com/v1',
      );
      expect(
        externalProviderConsentFingerprint(equivalent),
        externalProviderConsentFingerprint(_provider),
      );
    },
  );

  test(
    'external provider consent fingerprint changes with bound configuration',
    () {
      final baseline = externalProviderConsentFingerprint(_provider);

      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(baseUrl: 'https://other.example.com/v1'),
        ),
        isNot(baseline),
      );
      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(modelName: 'gpt-4.1'),
        ),
        isNot(baseline),
      );
      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(providerType: ExternalProviderType.ollama),
        ),
        isNot(baseline),
      );
      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(id: 'provider-2'),
        ),
        isNot(baseline),
      );
      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(apiKey: 'rotated-key'),
        ),
        isNot(baseline),
      );
    },
  );

  test('private policy changes invalidate only private consent', () {
    final changed = _provider.copyWith(allowSensitiveFields: true);

    expect(
      externalProviderConsentFingerprint(
        changed,
        scope: ExternalProviderConsentScope.standard,
      ),
      externalProviderConsentFingerprint(
        _provider,
        scope: ExternalProviderConsentScope.standard,
      ),
    );
    expect(
      externalProviderConsentFingerprint(
        changed,
        scope: ExternalProviderConsentScope.privateContext,
      ),
      isNot(
        externalProviderConsentFingerprint(
          _provider,
          scope: ExternalProviderConsentScope.privateContext,
        ),
      ),
    );
  });

  test(
    'external privacy confirmation is bound to the current config fingerprint',
    () async {
      SharedPreferences.setMockInitialValues({
        'ai.external_privacy_ack.provider-1': true,
      });
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderConsentStoreProvider.overrideWith(
            (ref) => const _SharedPreferencesConsentStore(),
          ),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(
        externalPrivacyConfirmationControllerProvider,
      );

      expect(
        await controller.hasAcknowledged(
          _provider,
          includesPrivateContext: false,
        ),
        isFalse,
      );
      await controller.markAcknowledged(
        _provider,
        includesPrivateContext: false,
      );
      expect(
        await controller.hasAcknowledged(
          _provider,
          includesPrivateContext: false,
        ),
        isTrue,
      );
      expect(
        await controller.hasAcknowledged(
          _provider,
          includesPrivateContext: true,
        ),
        isFalse,
      );
      expect(
        await controller.hasAcknowledged(
          _provider.copyWith(modelName: 'gpt-4.1'),
          includesPrivateContext: false,
        ),
        isFalse,
      );
      await controller.revoke(_provider);
      expect(
        await controller.hasAcknowledged(
          _provider,
          includesPrivateContext: false,
        ),
        isFalse,
      );
    },
  );
}

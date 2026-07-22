abstract final class DatabaseSchemaV7 {
  static const String actualBackendColumn = 'actual_backend';
  static const String actualModelColumn = 'actual_model';
  static const String providerFingerprintColumn = 'provider_fingerprint';

  static const String addActualBackendStatement =
      'ALTER TABLE chat_messages ADD COLUMN actual_backend TEXT';
  static const String addActualModelStatement =
      'ALTER TABLE chat_messages ADD COLUMN actual_model TEXT';
  static const String addProviderFingerprintStatement =
      'ALTER TABLE chat_messages ADD COLUMN provider_fingerprint TEXT';

  static const Map<String, String> provenanceColumnStatements =
      <String, String>{
        actualBackendColumn: addActualBackendStatement,
        actualModelColumn: addActualModelStatement,
        providerFingerprintColumn: addProviderFingerprintStatement,
      };

  static const String disableProviderConfigsStatement = '''
    UPDATE provider_configs
    SET enabled = 0
    WHERE enabled <> 0
    ''';

  static const String dropProviderEnabledIndexStatement =
      'DROP INDEX IF EXISTS uq_provider_configs_enabled_type';

  static const String createProviderEnabledIndexStatement = '''
    CREATE UNIQUE INDEX uq_provider_configs_enabled_type
    ON provider_configs(enabled)
    WHERE enabled = 1
    ''';

  static const List<String> migrationStatements = <String>[
    addActualBackendStatement,
    addActualModelStatement,
    addProviderFingerprintStatement,
    disableProviderConfigsStatement,
    dropProviderEnabledIndexStatement,
    createProviderEnabledIndexStatement,
  ];
}

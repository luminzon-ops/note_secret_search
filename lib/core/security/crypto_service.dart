import 'dart:typed_data';

abstract interface class CryptoService {
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  });

  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  });
}

class FieldCryptoContext {
  FieldCryptoContext({
    required this.table,
    required this.rowId,
    required this.column,
  }) {
    _validatePart(table, 'table');
    _validatePart(rowId, 'rowId');
    _validatePart(column, 'column');
  }

  final String table;
  final String rowId;
  final String column;

  static void _validatePart(String value, String name) {
    if (value.isEmpty || value != value.trim()) {
      throw ArgumentError.value(
        value,
        name,
        'Must be non-empty and contain no surrounding whitespace.',
      );
    }
  }
}

enum EncryptedDatabaseField {
  secretUsername('secret_items', 'username_ciphertext'),
  secretPassword('secret_items', 'password_ciphertext'),
  secretWebsiteUrl('secret_items', 'website_url_ciphertext'),
  secretNote('secret_items', 'note_ciphertext'),
  noteContent('note_items', 'content_ciphertext'),
  noteSummary('note_items', 'summary_ciphertext'),
  providerConfig('provider_configs', 'encrypted_config'),
  syncAccountConfig('sync_accounts', 'encrypted_config'),
  appSettingValue('app_settings', 'value_ciphertext');

  const EncryptedDatabaseField(this.table, this.column);

  final String table;
  final String column;

  FieldCryptoContext contextFor(String rowId) {
    return FieldCryptoContext(table: table, rowId: rowId, column: column);
  }
}

extension EncryptedDatabaseFieldAccess on CryptoService {
  Uint8List? encryptField(
    String? plaintext, {
    required EncryptedDatabaseField field,
    required String rowId,
  }) {
    return encryptNullable(plaintext, context: field.contextFor(rowId));
  }

  String decryptField(
    List<int>? ciphertext, {
    required EncryptedDatabaseField field,
    required String rowId,
  }) {
    return decryptNullable(ciphertext, context: field.contextFor(rowId));
  }
}

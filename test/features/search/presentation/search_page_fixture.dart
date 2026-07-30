part of 'search_page_test.dart';

class _FakeCryptoService implements CryptoService {
  const _FakeCryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    if (ciphertext == null) {
      return '';
    }
    return String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    return plaintext == null ? null : Uint8List.fromList(plaintext.codeUnits);
  }
}

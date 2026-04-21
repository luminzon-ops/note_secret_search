import 'dart:convert';

abstract interface class CryptoService {
  List<int>? encryptNullable(String? plaintext);

  String decryptNullable(List<int>? ciphertext);
}

class MvpCryptoService implements CryptoService {
  const MvpCryptoService();

  @override
  String decryptNullable(List<int>? ciphertext) {
    if (ciphertext == null || ciphertext.isEmpty) {
      return '';
    }

    return utf8.decode(ciphertext);
  }

  @override
  List<int>? encryptNullable(String? plaintext) {
    if (plaintext == null || plaintext.trim().isEmpty) {
      return null;
    }

    return utf8.encode(plaintext.trim());
  }
}

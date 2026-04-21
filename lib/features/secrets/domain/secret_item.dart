class SecretItem {
  const SecretItem({
    required this.id,
    required this.vaultId,
    required this.title,
    required this.usernameCiphertext,
    required this.passwordCiphertext,
    required this.websiteUrlCiphertext,
    required this.noteCiphertext,
    required this.tags,
    required this.categoryId,
    required this.favorite,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
    this.deletedAt,
  });

  final String id;
  final String vaultId;
  final String title;
  final List<int>? usernameCiphertext;
  final List<int>? passwordCiphertext;
  final List<int>? websiteUrlCiphertext;
  final List<int>? noteCiphertext;
  final List<String> tags;
  final String? categoryId;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;
  final DateTime? deletedAt;
}

class NoteItem {
  const NoteItem({
    required this.id,
    required this.vaultId,
    required this.title,
    required this.contentCiphertext,
    required this.summaryCacheCiphertext,
    required this.tags,
    required this.categoryId,
    required this.favorite,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String vaultId;
  final String title;
  final List<int> contentCiphertext;
  final List<int>? summaryCacheCiphertext;
  final List<String> tags;
  final String? categoryId;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class Tag {
  const Tag({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String vaultId;
  final String name;
  final DateTime createdAt;
}

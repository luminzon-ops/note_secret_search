class Category {
  const Category({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String vaultId;
  final String name;
  final int sortOrder;
}

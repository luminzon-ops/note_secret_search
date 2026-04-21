abstract class BaseEntity {
  const BaseEntity({
    required this.id,
    required this.vaultId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String vaultId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

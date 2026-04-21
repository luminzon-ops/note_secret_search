class Vault {
  const Vault({
    required this.id,
    required this.name,
    required this.description,
    required this.isDefault,
    required this.encryptionVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final bool isDefault;
  final int encryptionVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
}

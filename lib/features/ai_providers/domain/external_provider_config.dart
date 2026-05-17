enum ExternalProviderType { openAiCompatible }

class ExternalProviderConfig {
  const ExternalProviderConfig({
    required this.id,
    required this.providerType,
    required this.displayName,
    required this.baseUrl,
    required this.apiKey,
    required this.modelName,
    required this.embeddingModelName,
    required this.enabled,
    required this.allowSensitiveFields,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final ExternalProviderType providerType;
  final String displayName;
  final String baseUrl;
  final String apiKey;
  final String modelName;
  final String? embeddingModelName;
  final bool enabled;
  final bool allowSensitiveFields;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ExternalProviderConfig copyWith({
    String? id,
    ExternalProviderType? providerType,
    String? displayName,
    String? baseUrl,
    String? apiKey,
    String? modelName,
    String? embeddingModelName,
    bool clearEmbeddingModelName = false,
    bool? enabled,
    bool? allowSensitiveFields,
    DateTime? createdAt,
    bool clearCreatedAt = false,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return ExternalProviderConfig(
      id: id ?? this.id,
      providerType: providerType ?? this.providerType,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      embeddingModelName: clearEmbeddingModelName
          ? null
          : (embeddingModelName ?? this.embeddingModelName),
      enabled: enabled ?? this.enabled,
      allowSensitiveFields: allowSensitiveFields ?? this.allowSensitiveFields,
      createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'providerType': providerType.name,
      'displayName': displayName,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'modelName': modelName,
      'embeddingModelName': embeddingModelName,
      'enabled': enabled,
      'allowSensitiveFields': allowSensitiveFields,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  factory ExternalProviderConfig.fromJson(Map<String, Object?> json) {
    return ExternalProviderConfig(
      id: json['id']! as String,
      providerType: ExternalProviderType.values.byName(json['providerType']! as String),
      displayName: json['displayName']! as String,
      baseUrl: json['baseUrl']! as String,
      apiKey: json['apiKey']! as String,
      modelName: json['modelName']! as String,
      embeddingModelName: json['embeddingModelName'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      allowSensitiveFields: json['allowSensitiveFields'] as bool? ?? false,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['createdAt']! as int),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['updatedAt']! as int),
    );
  }
}

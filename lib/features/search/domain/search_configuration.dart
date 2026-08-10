import 'dart:convert';

import 'package:crypto/crypto.dart';

const int searchConfigurationFormatVersion = 1;
const int searchIndexConfigurationVersion = 1;
const Set<int> supportedSearchChunkLengths = <int>{160, 280, 400};

String searchIndexConfigurationHash(SearchConfiguration configuration) {
  return sha256
      .convert(utf8.encode(jsonEncode(configuration.indexProjectionJson())))
      .toString();
}

class SearchConfiguration {
  SearchConfiguration({
    required this.formatVersion,
    required this.configurationEpoch,
    required this.includeTitle,
    required this.includeSecretNote,
    required this.includePasswordField,
    required this.includeUsername,
    required this.includeUrl,
    required this.includeTags,
    required this.includeNoteBody,
    required this.allowLocalEmbedding,
    required this.allowExternalProviderAccess,
    required this.autoIndexEnabled,
    required this.maxChunkLength,
  }) {
    _validate();
  }

  factory SearchConfiguration.defaults() {
    return SearchConfiguration(
      formatVersion: searchConfigurationFormatVersion,
      configurationEpoch: 1,
      includeTitle: true,
      includeSecretNote: true,
      includePasswordField: false,
      includeUsername: true,
      includeUrl: true,
      includeTags: true,
      includeNoteBody: true,
      allowLocalEmbedding: true,
      allowExternalProviderAccess: false,
      autoIndexEnabled: true,
      maxChunkLength: 280,
    );
  }

  factory SearchConfiguration.fromJson(Map<String, Object?> json) {
    try {
      return SearchConfiguration(
        formatVersion: json['formatVersion']! as int,
        configurationEpoch: json['configurationEpoch']! as int,
        includeTitle: json['includeTitle']! as bool,
        includeSecretNote: json['includeSecretNote']! as bool,
        includePasswordField: json['includePasswordField']! as bool,
        includeUsername: json['includeUsername']! as bool,
        includeUrl: json['includeUrl']! as bool,
        includeTags: json['includeTags']! as bool,
        includeNoteBody: json['includeNoteBody']! as bool,
        allowLocalEmbedding: json['allowLocalEmbedding']! as bool,
        allowExternalProviderAccess:
            json['allowExternalProviderAccess']! as bool,
        autoIndexEnabled: json['autoIndexEnabled']! as bool,
        maxChunkLength: json['maxChunkLength']! as int,
      );
    } on Object catch (error) {
      if (error is FormatException) {
        rethrow;
      }
      throw const FormatException('Invalid search configuration.');
    }
  }

  final int formatVersion;
  final int configurationEpoch;
  final bool includeTitle;
  final bool includeSecretNote;
  final bool includePasswordField;
  final bool includeUsername;
  final bool includeUrl;
  final bool includeTags;
  final bool includeNoteBody;
  final bool allowLocalEmbedding;
  final bool allowExternalProviderAccess;
  final bool autoIndexEnabled;
  final int maxChunkLength;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'formatVersion': formatVersion,
      'configurationEpoch': configurationEpoch,
      'includeTitle': includeTitle,
      'includeSecretNote': includeSecretNote,
      'includePasswordField': includePasswordField,
      'includeUsername': includeUsername,
      'includeUrl': includeUrl,
      'includeTags': includeTags,
      'includeNoteBody': includeNoteBody,
      'allowLocalEmbedding': allowLocalEmbedding,
      'allowExternalProviderAccess': allowExternalProviderAccess,
      'autoIndexEnabled': autoIndexEnabled,
      'maxChunkLength': maxChunkLength,
    };
  }

  Map<String, Object?> indexProjectionJson() {
    return <String, Object?>{
      'indexConfigVersion': searchIndexConfigurationVersion,
      'includeTitle': includeTitle,
      'includeSecretNote': includeSecretNote,
      'includeUsername': includeUsername,
      'includeUrl': includeUrl,
      'includeTags': includeTags,
      'includeNoteBody': includeNoteBody,
      'allowLocalEmbedding': allowLocalEmbedding,
      'maxChunkLength': maxChunkLength,
    };
  }

  SearchConfiguration forSavedUpdate(SearchConfiguration desired) {
    final nextEpoch = _sameIndexProjection(desired)
        ? configurationEpoch
        : configurationEpoch + 1;
    return desired.copyWith(
      formatVersion: searchConfigurationFormatVersion,
      configurationEpoch: nextEpoch,
    );
  }

  SearchConfiguration copyWith({
    int? formatVersion,
    int? configurationEpoch,
    bool? includeTitle,
    bool? includeSecretNote,
    bool? includePasswordField,
    bool? includeUsername,
    bool? includeUrl,
    bool? includeTags,
    bool? includeNoteBody,
    bool? allowLocalEmbedding,
    bool? allowExternalProviderAccess,
    bool? autoIndexEnabled,
    int? maxChunkLength,
  }) {
    return SearchConfiguration(
      formatVersion: formatVersion ?? this.formatVersion,
      configurationEpoch: configurationEpoch ?? this.configurationEpoch,
      includeTitle: includeTitle ?? this.includeTitle,
      includeSecretNote: includeSecretNote ?? this.includeSecretNote,
      includePasswordField: includePasswordField ?? this.includePasswordField,
      includeUsername: includeUsername ?? this.includeUsername,
      includeUrl: includeUrl ?? this.includeUrl,
      includeTags: includeTags ?? this.includeTags,
      includeNoteBody: includeNoteBody ?? this.includeNoteBody,
      allowLocalEmbedding: allowLocalEmbedding ?? this.allowLocalEmbedding,
      allowExternalProviderAccess:
          allowExternalProviderAccess ?? this.allowExternalProviderAccess,
      autoIndexEnabled: autoIndexEnabled ?? this.autoIndexEnabled,
      maxChunkLength: maxChunkLength ?? this.maxChunkLength,
    );
  }

  bool _sameIndexProjection(SearchConfiguration other) {
    return includeTitle == other.includeTitle &&
        includeSecretNote == other.includeSecretNote &&
        includeUsername == other.includeUsername &&
        includeUrl == other.includeUrl &&
        includeTags == other.includeTags &&
        includeNoteBody == other.includeNoteBody &&
        allowLocalEmbedding == other.allowLocalEmbedding &&
        maxChunkLength == other.maxChunkLength;
  }

  void _validate() {
    if (formatVersion != searchConfigurationFormatVersion ||
        configurationEpoch < 0 ||
        !supportedSearchChunkLengths.contains(maxChunkLength)) {
      throw const FormatException('Invalid search configuration.');
    }
  }
}

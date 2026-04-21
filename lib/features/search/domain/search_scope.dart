class SearchScopeConfig {
  const SearchScopeConfig({
    required this.includeTitle,
    required this.includeSecretNote,
    required this.includePasswordField,
    required this.includeUsername,
    required this.includeUrl,
    required this.includeTags,
    required this.includeNoteBody,
    required this.allowLocalEmbedding,
    required this.allowExternalProviderAccess,
  });

  final bool includeTitle;
  final bool includeSecretNote;
  final bool includePasswordField;
  final bool includeUsername;
  final bool includeUrl;
  final bool includeTags;
  final bool includeNoteBody;
  final bool allowLocalEmbedding;
  final bool allowExternalProviderAccess;

  const SearchScopeConfig.defaults()
      : includeTitle = true,
        includeSecretNote = true,
        includePasswordField = false,
        includeUsername = true,
        includeUrl = true,
        includeTags = true,
        includeNoteBody = true,
        allowLocalEmbedding = true,
        allowExternalProviderAccess = false;

  SearchScopeConfig copyWith({
    bool? includeTitle,
    bool? includeSecretNote,
    bool? includePasswordField,
    bool? includeUsername,
    bool? includeUrl,
    bool? includeTags,
    bool? includeNoteBody,
    bool? allowLocalEmbedding,
    bool? allowExternalProviderAccess,
  }) {
    return SearchScopeConfig(
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
    );
  }
}

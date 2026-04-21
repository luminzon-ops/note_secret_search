class SearchIndexSettings {
  const SearchIndexSettings({
    required this.autoIndexEnabled,
    required this.includeSecretNotes,
    required this.includeNoteBody,
    required this.maxChunkLength,
  });

  const SearchIndexSettings.defaults()
      : autoIndexEnabled = true,
        includeSecretNotes = true,
        includeNoteBody = true,
        maxChunkLength = 280;

  final bool autoIndexEnabled;
  final bool includeSecretNotes;
  final bool includeNoteBody;
  final int maxChunkLength;

  SearchIndexSettings copyWith({
    bool? autoIndexEnabled,
    bool? includeSecretNotes,
    bool? includeNoteBody,
    int? maxChunkLength,
  }) {
    return SearchIndexSettings(
      autoIndexEnabled: autoIndexEnabled ?? this.autoIndexEnabled,
      includeSecretNotes: includeSecretNotes ?? this.includeSecretNotes,
      includeNoteBody: includeNoteBody ?? this.includeNoteBody,
      maxChunkLength: maxChunkLength ?? this.maxChunkLength,
    );
  }
}

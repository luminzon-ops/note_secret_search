class SearchIndexSettings {
  const SearchIndexSettings({
    required this.autoIndexEnabled,
    required this.maxChunkLength,
  });

  const SearchIndexSettings.defaults()
    : autoIndexEnabled = true,
      maxChunkLength = 280;

  final bool autoIndexEnabled;
  final int maxChunkLength;

  SearchIndexSettings copyWith({bool? autoIndexEnabled, int? maxChunkLength}) {
    return SearchIndexSettings(
      autoIndexEnabled: autoIndexEnabled ?? this.autoIndexEnabled,
      maxChunkLength: maxChunkLength ?? this.maxChunkLength,
    );
  }
}

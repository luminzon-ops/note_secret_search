import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';

class SearchSettingsImpactPreview {
  const SearchSettingsImpactPreview({
    required this.headline,
    required this.description,
    required this.immediateItems,
    required this.reindexItems,
    this.recommendation,
  });

  final String headline;
  final String description;
  final List<String> immediateItems;
  final List<String> reindexItems;
  final String? recommendation;
}

SearchSettingsImpactPreview buildSearchSettingsImpactPreview({
  required SearchScopeConfig savedScope,
  required SearchScopeConfig draftScope,
  required SearchIndexSettings savedIndexSettings,
  required SearchIndexSettings draftIndexSettings,
  required SearchIndexStatus indexStatus,
}) {
  final immediateItems = <String>[];
  final reindexItems = <String>[];

  void addIfChanged(bool changed, List<String> target, String label) {
    if (changed) {
      target.add(label);
    }
  }

  addIfChanged(savedScope.includeTitle != draftScope.includeTitle, immediateItems, '标题检索范围');
  addIfChanged(savedScope.includeSecretNote != draftScope.includeSecretNote, immediateItems, '密码附注检索范围');
  addIfChanged(savedScope.includePasswordField != draftScope.includePasswordField, immediateItems, '密码字段检索范围');
  addIfChanged(savedScope.includeUsername != draftScope.includeUsername, immediateItems, '账号字段检索范围');
  addIfChanged(savedScope.includeUrl != draftScope.includeUrl, immediateItems, '网址字段检索范围');
  addIfChanged(savedScope.includeTags != draftScope.includeTags, immediateItems, '标签检索范围');
  addIfChanged(savedScope.includeNoteBody != draftScope.includeNoteBody, immediateItems, '笔记正文检索范围');
  addIfChanged(savedScope.allowLocalEmbedding != draftScope.allowLocalEmbedding, immediateItems, '本地语义检索开关');
  addIfChanged(
    savedScope.allowExternalProviderAccess != draftScope.allowExternalProviderAccess,
    immediateItems,
    '外部模型访问开关',
  );

  addIfChanged(
    savedIndexSettings.includeSecretNotes != draftIndexSettings.includeSecretNotes,
    reindexItems,
    '索引密码附注',
  );
  addIfChanged(
    savedIndexSettings.includeNoteBody != draftIndexSettings.includeNoteBody,
    reindexItems,
    '索引笔记正文',
  );
  addIfChanged(
    savedIndexSettings.maxChunkLength != draftIndexSettings.maxChunkLength,
    reindexItems,
    '单 chunk 最大长度',
  );

  if (immediateItems.isEmpty && reindexItems.isEmpty) {
    return const SearchSettingsImpactPreview(
      headline: '这些设置会如何影响结果',
      description: '检索范围类设置会立即影响结果；索引内容类设置在你下次重建索引后生效。',
      immediateItems: <String>[],
      reindexItems: <String>[],
    );
  }

  if (immediateItems.isNotEmpty && reindexItems.isEmpty) {
    return SearchSettingsImpactPreview(
      headline: '这些设置会如何影响结果',
      description: '你当前的草稿会立即影响搜索结果。保存后可以直接回到搜索页查看变化。',
      immediateItems: immediateItems,
      reindexItems: const <String>[],
      recommendation: '保存后可以直接返回搜索页查看变化。',
    );
  }

  if (immediateItems.isEmpty && reindexItems.isNotEmpty) {
    return SearchSettingsImpactPreview(
      headline: '这些设置会如何影响结果',
      description: '你当前的草稿会影响语义索引内容。保存后需要重新索引，语义结果才会更新。',
      immediateItems: const <String>[],
      reindexItems: reindexItems,
      recommendation: indexStatus.pendingItems.isNotEmpty
          ? '当前已有待索引内容，建议保存后直接刷新索引。'
          : '保存后建议尽快重建索引，再判断语义结果变化。',
    );
  }

  return SearchSettingsImpactPreview(
    headline: '这些设置会如何影响结果',
    description: '你当前的草稿包含两类影响：部分改动会立即影响结果，部分改动需要重新索引后生效。',
    immediateItems: immediateItems,
    reindexItems: reindexItems,
    recommendation: indexStatus.pendingItems.isNotEmpty ? '当前已有待索引内容，建议保存后直接刷新索引。' : null,
  );
}

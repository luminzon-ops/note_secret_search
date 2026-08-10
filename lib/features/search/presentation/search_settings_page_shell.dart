part of 'search_settings_page.dart';

class SearchSettingsPage extends ConsumerStatefulWidget {
  const SearchSettingsPage({super.key});

  @override
  ConsumerState<SearchSettingsPage> createState() => _SearchSettingsPageState();
}

class _SearchSettingsPageState extends ConsumerState<SearchSettingsPage> {
  SearchScopeConfig? _draftScope;
  SearchIndexSettings? _draftIndexSettings;

  Future<void> _triggerPostSaveRefresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(searchRefreshControllerProvider.notifier)
          .refresh(ref.read(searchQueryProvider));
      if (result != SearchRefreshExecutionResult.completed) {
        return;
      }
      if (!messenger.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('已开始处理待索引内容，请稍后查看最新结果。')),
      );
    } catch (_) {
      if (!messenger.mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('索引触发失败，请稍后重试。')));
    }
  }

  void _returnToSearch(BuildContext context) {
    ref.read(searchRefreshControllerProvider.notifier).publishHandoff();
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppDestination.search);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final scopeAsync = ref.watch(searchScopeConfigProvider);
    final semanticReadinessAsync = ref.watch(semanticSearchReadinessProvider);
    final indexStatusAsync = ref.watch(searchIndexStatusProvider);
    final indexSettingsAsync = ref.watch(searchIndexSettingsProvider);
    final refreshSession = ref.watch(searchRefreshSessionProvider);
    final refreshState = ref.watch(searchRefreshControllerProvider);

    final savedScope = scopeAsync.valueOrNull;
    final savedIndexSettings = indexSettingsAsync.valueOrNull;
    if (savedScope != null && _draftScope == null) {
      _draftScope = savedScope;
    }
    if (savedIndexSettings != null && _draftIndexSettings == null) {
      _draftIndexSettings = savedIndexSettings;
    }

    final alignedSummary =
        semanticReadinessAsync.hasValue && indexStatusAsync.hasValue
        ? buildSearchStatusSummary(
            readiness: semanticReadinessAsync.requireValue,
            status: indexStatusAsync.requireValue,
          )
        : null;

    final impactPreview =
        savedScope != null &&
            savedIndexSettings != null &&
            _draftScope != null &&
            _draftIndexSettings != null &&
            indexStatusAsync.hasValue
        ? buildSearchSettingsImpactPreview(
            savedScope: savedScope,
            draftScope: _draftScope!,
            savedIndexSettings: savedIndexSettings,
            draftIndexSettings: _draftIndexSettings!,
            indexStatus: indexStatusAsync.requireValue,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('搜索与索引设置')),
      bottomNavigationBar:
          refreshState.postSaveNeedsReindex && !refreshSession.refreshing
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '设置已保存，语义结果需要刷新索引后更新。',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: () => _triggerPostSaveRefresh(context),
                              child: const Text('立即刷新'),
                            ),
                            TextButton(
                              onPressed: () => _returnToSearch(context),
                              child: const Text('返回搜索'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (semanticReadinessAsync.hasValue &&
              scopeAsync.hasValue &&
              indexStatusAsync.hasValue)
            _SemanticReadinessCard(
              readiness: semanticReadinessAsync.requireValue,
              scope: scopeAsync.requireValue,
              indexStatus: indexStatusAsync.requireValue,
              summary: alignedSummary!,
              refreshSession: refreshSession,
            )
          else if (semanticReadinessAsync.hasError)
            Text(semanticReadinessAsync.error.toString())
          else if (scopeAsync.hasError)
            Text(scopeAsync.error.toString())
          else if (indexStatusAsync.hasError)
            Text(indexStatusAsync.error.toString())
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          indexStatusAsync.when(
            data: (status) => alignedSummary == null
                ? const SizedBox.shrink()
                : _IndexStatusCard(
                    status: status,
                    summary: alignedSummary,
                    refreshSession: refreshSession,
                  ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          if (impactPreview != null)
            _SearchSettingsImpactPreviewCard(preview: impactPreview)
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          indexSettingsAsync.when(
            data: (settings) => _IndexSettingsCard(
              settings: _draftIndexSettings ?? settings,
              onChanged: (next) => setState(() {
                _draftIndexSettings = next;
                ref
                    .read(searchRefreshControllerProvider.notifier)
                    .clearPostSaveReindex();
              }),
              onSave: () async {
                final draft = _draftIndexSettings;
                if (draft == null) {
                  return;
                }
                final result = await ref
                    .read(searchSettingsUseCaseProvider)
                    .saveIndexSettings(draft);
                if (!mounted) {
                  return;
                }
                ref
                    .read(searchRefreshControllerProvider.notifier)
                    .recordSettingsSaved(result);
                setState(() {
                  _draftIndexSettings = draft;
                });
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          scopeAsync.when(
            data: (scope) => _SearchScopeCard(
              scope: _draftScope ?? scope,
              onChanged: (next) => setState(() {
                _draftScope = next;
                ref
                    .read(searchRefreshControllerProvider.notifier)
                    .clearPostSaveReindex();
              }),
              onSave: () async {
                final draft = _draftScope;
                if (draft == null) {
                  return;
                }
                final result = await ref
                    .read(searchSettingsUseCaseProvider)
                    .saveScope(draft);
                if (!mounted) {
                  return;
                }
                ref
                    .read(searchRefreshControllerProvider.notifier)
                    .recordSettingsSaved(result);
                setState(() {
                  _draftScope = draft;
                });
              },
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(error.toString()),
          ),
        ],
      ),
    );
  }
}

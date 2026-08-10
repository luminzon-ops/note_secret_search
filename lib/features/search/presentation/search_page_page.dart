part of 'search_page.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unifiedResultsAsync = ref.watch(unifiedSearchResultsProvider);
    final semanticResultsAsync = ref.watch(semanticSearchResultsProvider);
    final readinessAsync = ref.watch(semanticSearchReadinessProvider);
    final indexStatusAsync = ref.watch(searchIndexStatusProvider);
    final refreshSession = ref.watch(searchRefreshSessionProvider);
    final refreshFeedback = ref.watch(searchRefreshFeedbackProvider);
    final pendingReindexHandoff = ref.watch(
      searchPendingReindexHandoffProvider,
    );
    final query = ref.watch(searchQueryProvider).trim();
    final fusionService = ref.watch(searchFusionServiceProvider);
    final fusionDiagnostics =
        unifiedResultsAsync.hasValue && semanticResultsAsync.hasValue
        ? fusionService.diagnoseFinalResults(
            unifiedResults: unifiedResultsAsync.requireValue,
            semanticResults: semanticResultsAsync.requireValue,
          )
        : null;
    final admittedSemanticResults =
        unifiedResultsAsync.hasValue && semanticResultsAsync.hasValue
        ? fusionService.admittedSemanticResultsForFinalResults(
            unifiedResults: unifiedResultsAsync.requireValue,
            semanticResults: semanticResultsAsync.requireValue,
          )
        : const <SemanticSearchResult>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        actions: [
          IconButton(
            tooltip: '搜索设置与索引',
            onPressed: () => context.push(AppDestination.searchSettings),
            icon: const Icon(Icons.tune_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SearchBar(
            controller: _controller,
            hintText: '搜索密码、标签、笔记或语义描述',
            leading: const Icon(Icons.search),
            onChanged: (value) =>
                ref.read(searchQueryProvider.notifier).state = value,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: const Icon(Icons.tune_outlined),
              title: const Text('搜索设置与索引'),
              subtitle: const Text('调整检索范围、语义索引策略与隐私控制'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppDestination.searchSettings),
            ),
          ),
          const SizedBox(height: 16),
          if (pendingReindexHandoff.visible)
            _SearchPendingReindexHandoffCard(handoff: pendingReindexHandoff)
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          readinessAsync.when(
            data: (readiness) => indexStatusAsync.when(
              data: (status) => _SearchStatusCard(
                summary: buildSearchStatusSummary(
                  readiness: readiness,
                  status: status,
                ),
                refreshSession: refreshSession,
              ),
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => Text(error.toString()),
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          if (_shouldShowRefreshFeedback(
            query: query,
            feedback: refreshFeedback,
            refreshSession: refreshSession,
          ))
            _SearchRefreshFeedbackCard(feedback: refreshFeedback)
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          if (unifiedResultsAsync.hasValue && semanticResultsAsync.hasValue)
            _SearchFeedbackCard(
              query: query,
              readiness: readinessAsync.valueOrNull,
              unifiedResults: unifiedResultsAsync.requireValue,
              semanticResults: admittedSemanticResults,
            )
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          if (unifiedResultsAsync.hasValue && semanticResultsAsync.hasValue)
            _SearchPipelineSummaryCard(
              unifiedResults: unifiedResultsAsync.requireValue,
              semanticResults: admittedSemanticResults,
              fusionDiagnostics: fusionDiagnostics,
            )
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          unifiedResultsAsync.when(
            data: (results) => _SearchResultSection(results: results),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          semanticResultsAsync.when(
            data: (_) =>
                _SemanticSearchSection(results: admittedSemanticResults),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
        ],
      ),
    );
  }

  bool _shouldShowRefreshFeedback({
    required String query,
    required SearchRefreshFeedbackState feedback,
    required SearchRefreshSessionState refreshSession,
  }) {
    if (refreshSession.refreshing || !feedback.visible) {
      return false;
    }

    if (feedback.queryAtRefresh == null) {
      return false;
    }

    return feedback.queryAtRefresh == query;
  }
}

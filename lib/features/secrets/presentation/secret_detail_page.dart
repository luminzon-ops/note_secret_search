import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/presentation/detail_search_hit_target.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

class SecretDetailPage extends ConsumerWidget {
  const SecretDetailPage({
    required this.secretId,
    this.searchQuery,
    this.searchSource,
    this.searchContext,
    super.key,
  });

  final String secretId;
  final String? searchQuery;
  final String? searchSource;
  final String? searchContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secretAsync = ref.watch(secretDetailProvider(secretId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('密码详情'),
        actions: [
          IconButton(
            onPressed: () => context.push('/vault/secret/$secretId/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () => _delete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: secretAsync.when(
        data: (secret) {
          if (secret == null) {
            return const Center(child: Text('条目不存在或已删除'));
          }
          return _SecretDetailBody(
            secret: secret,
            cryptoService: ref.read(cryptoServiceProvider),
            searchQuery: searchQuery,
            searchSource: searchSource,
            searchContext: searchContext,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    await ref.read(secretRepositoryProvider).softDelete(secretId);
    ref.invalidate(secretListProvider);
    ref.invalidate(secretDetailProvider(secretId));
    ref.invalidate(searchIndexStatusProvider);
    ref.invalidate(semanticSearchResultsProvider);
    ref.invalidate(unifiedSearchResultsProvider);

    final activeModel = await ref.read(activeEmbeddingModelProvider.future);
    final indexSettings = await ref.read(searchIndexSettingsProvider.future);
    if (activeModel != null && indexSettings.autoIndexEnabled) {
      await ref.read(searchIndexControllerProvider).indexPending();
      ref.invalidate(searchIndexStatusProvider);
      ref.invalidate(semanticSearchResultsProvider);
      ref.invalidate(unifiedSearchResultsProvider);
    }

    if (context.mounted) {
      context.pop();
    }
  }
}

class _SecretDetailBody extends StatefulWidget {
  const _SecretDetailBody({
    required this.secret,
    required this.cryptoService,
    this.searchQuery,
    this.searchSource,
    this.searchContext,
  });

  final SecretItem secret;
  final dynamic cryptoService;
  final String? searchQuery;
  final String? searchSource;
  final String? searchContext;

  @override
  State<_SecretDetailBody> createState() => _SecretDetailBodyState();
}

class _SecretDetailBodyState extends State<_SecretDetailBody> {
  bool _didScrollToHit = false;

  @override
  Widget build(BuildContext context) {
    final secret = widget.secret;
    final cryptoService = widget.cryptoService;
    final searchQuery = widget.searchQuery;
    final searchSource = widget.searchSource;
    final searchContext = widget.searchContext;
    final searchFocusHint = resolveSecretDetailSearchFocusHint(searchContext);
    final searchHitExplanation = resolveSecretDetailHitExplanation(searchContext) ?? searchContext;
    final semanticOnlyHandoffHint = _semanticOnlyHandoffHint(searchSource);
    final hitTarget = resolveSecretDetailSearchHitTarget(searchContext);
    final titleKey = hitTarget == SecretDetailSearchHitTarget.title ? GlobalKey() : null;
    final usernameKey = hitTarget == SecretDetailSearchHitTarget.username ? GlobalKey() : null;
    final websiteKey = hitTarget == SecretDetailSearchHitTarget.website ? GlobalKey() : null;
    final tagsKey = hitTarget == SecretDetailSearchHitTarget.tags ? GlobalKey() : null;
    final noteKey = hitTarget == SecretDetailSearchHitTarget.note ? GlobalKey() : null;

    final scrollTargetKey = switch (hitTarget) {
      SecretDetailSearchHitTarget.title => titleKey,
      SecretDetailSearchHitTarget.username => usernameKey,
      SecretDetailSearchHitTarget.website => websiteKey,
      SecretDetailSearchHitTarget.tags => tagsKey,
      SecretDetailSearchHitTarget.note => noteKey,
      SecretDetailSearchHitTarget.none => null,
    };

    if (!_didScrollToHit && scrollTargetKey?.currentContext != null) {
      _didScrollToHit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = scrollTargetKey?.currentContext;
        if (targetContext != null && mounted) {
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 180),
            alignment: 0.18,
            curve: Curves.easeOut,
          );
        }
      });
    }

    final username = cryptoService.decryptNullable(secret.usernameCiphertext) as String;
    final password = cryptoService.decryptNullable(secret.passwordCiphertext) as String;
    final website = cryptoService.decryptNullable(secret.websiteUrlCiphertext) as String;
    final note = cryptoService.decryptNullable(secret.noteCiphertext) as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if ((searchSource ?? '').isNotEmpty || (searchQuery ?? '').isNotEmpty || (searchContext ?? '').isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('来自搜索'),
                    if ((searchSource ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('命中方式：${_searchSourceLabel(searchSource)}'),
                    ],
                    if ((searchQuery ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('查询词：$searchQuery'),
                    ],
                    if ((searchContext ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('命中说明：$searchHitExplanation'),
                    ],
                    if (searchFocusHint != null) ...[
                      const SizedBox(height: 8),
                      Text('优先查看：$searchFocusHint'),
                    ],
                    if (semanticOnlyHandoffHint != null) ...[
                      const SizedBox(height: 8),
                      Text('承接说明：$semanticOnlyHandoffHint'),
                    ],
                  ],
                ),
              ),
          ),
        if ((searchSource ?? '').isNotEmpty || (searchQuery ?? '').isNotEmpty || (searchContext ?? '').isNotEmpty)
          const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _wrapHighlightedSection(
                  context,
                  key: titleKey,
                  markerKey: hitTarget == SecretDetailSearchHitTarget.title
                      ? const ValueKey('secret-hit-title')
                      : null,
                  child: Text(secret.title, style: Theme.of(context).textTheme.headlineSmall),
                ),
                const SizedBox(height: 16),
                _SecretDetailRow(
                  label: '账号',
                  value: username,
                  highlightKey: usernameKey,
                  highlightMarkerKey: hitTarget == SecretDetailSearchHitTarget.username
                      ? const ValueKey('secret-hit-username')
                      : null,
                ),
                _SecretDetailRow(label: '密码', value: password, obscure: true),
                _SecretDetailRow(
                  label: '网址',
                  value: website,
                  highlightKey: websiteKey,
                  highlightMarkerKey: hitTarget == SecretDetailSearchHitTarget.website
                      ? const ValueKey('secret-hit-website')
                      : null,
                ),
                _SecretDetailRow(
                  label: '标签',
                  value: secret.tags.join(', '),
                  highlightKey: tagsKey,
                  highlightMarkerKey: hitTarget == SecretDetailSearchHitTarget.tags
                      ? const ValueKey('secret-hit-tags')
                      : null,
                ),
                _SecretDetailRow(
                  label: '备注',
                  value: note,
                  highlightKey: noteKey,
                  highlightMarkerKey: hitTarget == SecretDetailSearchHitTarget.note
                      ? const ValueKey('secret-hit-note')
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _searchSourceLabel(String? source) {
    switch (source) {
      case 'keyword_semantic':
        return '双命中';
      case 'semantic':
        return '语义命中';
      case 'keyword':
      default:
        return '关键词优先';
    }
  }

  String? _semanticOnlyHandoffHint(String? source) {
    if (source != 'semantic') {
      return null;
    }

    return '该结果以语义命中进入详情页，建议结合命中字段与正文继续确认。';
  }

  Widget _wrapHighlightedSection(
    BuildContext context, {
    required Widget child,
    required GlobalKey? key,
    required Key? markerKey,
  }) {
    final highlight = markerKey != null;
    return Container(
      key: key,
      width: double.infinity,
      margin: highlight ? const EdgeInsets.only(bottom: 4) : null,
      padding: highlight ? const EdgeInsets.all(8) : EdgeInsets.zero,
      decoration: highlight
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (markerKey != null) SizedBox(key: markerKey, width: 0, height: 0),
          child,
        ],
      ),
    );
  }
}

class _SecretDetailRow extends StatefulWidget {
  const _SecretDetailRow({
    required this.label,
    required this.value,
    this.obscure = false,
    this.highlightKey,
    this.highlightMarkerKey,
  });

  final String label;
  final String value;
  final bool obscure;
  final GlobalKey? highlightKey;
  final Key? highlightMarkerKey;

  @override
  State<_SecretDetailRow> createState() => _SecretDetailRowState();
}

class _SecretDetailRowState extends State<_SecretDetailRow> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final display = widget.obscure && !_revealed && widget.value.isNotEmpty
        ? '••••••••'
        : (widget.value.isEmpty ? '未填写' : widget.value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: widget.highlightKey,
        padding: widget.highlightMarkerKey != null ? const EdgeInsets.all(8) : EdgeInsets.zero,
        decoration: widget.highlightMarkerKey != null
            ? BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Column(
          children: [
            if (widget.highlightMarkerKey != null)
              SizedBox(key: widget.highlightMarkerKey, width: 0, height: 0),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 72, child: Text(widget.label)),
                Expanded(child: Text(display)),
                if (widget.obscure)
                  IconButton(
                    onPressed: () => setState(() => _revealed = !_revealed),
                    icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility),
                  ),
                IconButton(
                  onPressed: widget.value.isEmpty
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(ClipboardData(text: widget.value));
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('${widget.label}已复制')),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

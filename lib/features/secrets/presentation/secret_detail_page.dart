import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_editor_page.dart';

class SecretDetailPage extends ConsumerWidget {
  const SecretDetailPage({required this.secretId, super.key});

  final String secretId;

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

class _SecretDetailBody extends StatelessWidget {
  const _SecretDetailBody({
    required this.secret,
    required this.cryptoService,
  });

  final SecretItem secret;
  final dynamic cryptoService;

  @override
  Widget build(BuildContext context) {
    final username = cryptoService.decryptNullable(secret.usernameCiphertext) as String;
    final password = cryptoService.decryptNullable(secret.passwordCiphertext) as String;
    final website = cryptoService.decryptNullable(secret.websiteUrlCiphertext) as String;
    final note = cryptoService.decryptNullable(secret.noteCiphertext) as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(secret.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                _SecretDetailRow(label: '账号', value: username),
                _SecretDetailRow(label: '密码', value: password, obscure: true),
                _SecretDetailRow(label: '网址', value: website),
                _SecretDetailRow(label: '标签', value: secret.tags.join(', ')),
                _SecretDetailRow(label: '备注', value: note),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SecretDetailRow extends StatefulWidget {
  const _SecretDetailRow({
    required this.label,
    required this.value,
    this.obscure = false,
  });

  final String label;
  final String value;
  final bool obscure;

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
      child: Row(
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
    );
  }
}

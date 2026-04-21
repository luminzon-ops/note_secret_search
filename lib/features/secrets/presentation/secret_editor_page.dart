import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/secrets/application/secret_form_mapper.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_draft.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

class SecretEditorPage extends ConsumerStatefulWidget {
  const SecretEditorPage({
    this.secretId,
    super.key,
  });

  final String? secretId;

  bool get isEditing => secretId != null;

  @override
  ConsumerState<SecretEditorPage> createState() => _SecretEditorPageState();
}

class _SecretEditorPageState extends ConsumerState<SecretEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _websiteController = TextEditingController();
  final _noteController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _favorite = false;
  bool _initialized = false;

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _websiteController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secretAsync = widget.secretId == null
        ? const AsyncData<SecretItem?>(null)
        : ref.watch(secretDetailProvider(widget.secretId!));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑密码' : '新增密码'),
      ),
      body: secretAsync.when(
        data: (secret) {
          _hydrate(secret);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: '标题 *'),
                  validator: (value) => (value == null || value.trim().isEmpty) ? '请输入标题' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: '账号'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _websiteController,
                  decoration: const InputDecoration(labelText: '网址'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tagsController,
                  decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _favorite,
                  onChanged: (value) => setState(() => _favorite = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('收藏'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: '备注'),
                  maxLines: 6,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _submit(secret),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }

  void _hydrate(SecretItem? secret) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (secret == null) {
      return;
    }
    final draft = SecretFormMapper.toDraft(secret, ref.read(cryptoServiceProvider));
    _titleController.text = draft.title;
    _usernameController.text = draft.username;
    _passwordController.text = draft.password;
    _websiteController.text = draft.websiteUrl;
    _noteController.text = draft.note;
    _tagsController.text = draft.tags.join(', ');
    _favorite = draft.favorite;
  }

  Future<void> _submit(SecretItem? existing) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final vault = await ref.read(defaultVaultProvider.future);
    if (vault == null || !mounted) {
      return;
    }

    final draft = SecretDraft(
      title: _titleController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      websiteUrl: _websiteController.text,
      note: _noteController.text,
      tags: _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false),
      categoryId: null,
      favorite: _favorite,
    );

    final item = existing == null
        ? SecretFormMapper.create(
            vaultId: vault.id,
            draft: draft,
            cryptoService: ref.read(cryptoServiceProvider),
          )
        : SecretFormMapper.update(
            previous: existing,
            draft: draft,
            cryptoService: ref.read(cryptoServiceProvider),
          );

    await ref.read(secretRepositoryProvider).save(item);
    ref.invalidate(secretListProvider);
    ref.invalidate(secretDetailProvider(item.id));
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
    if (mounted) {
      context.pop();
    }
  }
}

final secretDetailProvider = FutureProvider.family<SecretItem?, String>((ref, id) async {
  return ref.watch(secretRepositoryProvider).getById(id);
});

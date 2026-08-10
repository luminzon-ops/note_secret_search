import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/notes/application/note_form_mapper.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_draft.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';

class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({this.noteId, super.key});

  final String? noteId;

  bool get isEditing => noteId != null;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _favorite = false;
  bool _initialized = false;

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noteAsync = widget.noteId == null
        ? const AsyncData<NoteItem?>(null)
        : ref.watch(noteDetailProvider(widget.noteId!));

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? '编辑笔记' : '新增笔记')),
      body: noteAsync.when(
        data: (note) {
          _hydrate(note);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: '标题 *'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? '请输入标题' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _summaryController,
                  decoration: const InputDecoration(labelText: '摘要（可选）'),
                  maxLines: 2,
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
                  controller: _contentController,
                  decoration: const InputDecoration(labelText: '正文 *'),
                  maxLines: 12,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? '请输入正文' : null,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _submit(note),
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

  void _hydrate(NoteItem? note) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (note == null) {
      return;
    }
    final draft = NoteFormMapper.toDraft(note, ref.read(cryptoServiceProvider));
    _titleController.text = draft.title;
    _summaryController.text = draft.summary;
    _contentController.text = draft.content;
    _tagsController.text = draft.tags.join(', ');
    _favorite = draft.favorite;
  }

  Future<void> _submit(NoteItem? existing) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final draft = NoteDraft(
      title: _titleController.text,
      content: _contentController.text,
      summary: _summaryController.text,
      tags: _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false),
      categoryId: null,
      favorite: _favorite,
    );

    final item = await ref
        .read(saveNoteUseCaseProvider)
        .execute(existing: existing, draft: draft);
    if (item != null && mounted) {
      context.pop();
    }
  }
}

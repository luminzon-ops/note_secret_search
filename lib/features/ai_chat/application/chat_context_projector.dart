import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';

enum ChatContextProjectionTarget { local, external }

class ProjectedChatContextItem {
  const ProjectedChatContextItem({
    required this.type,
    required this.title,
    required this.content,
  });

  final ChatContextItemType type;
  final String title;
  final String content;
}

abstract interface class ChatContextProjector {
  Future<List<ProjectedChatContextItem>> projectManual({
    required List<ChatContextItem> items,
    required SearchConfiguration configuration,
    required ChatContextProjectionTarget target,
  });
}

class RepositoryChatContextProjector implements ChatContextProjector {
  const RepositoryChatContextProjector({
    required SecretRepository secretRepository,
    required NoteRepository noteRepository,
    required CryptoService cryptoService,
  }) : _secretRepository = secretRepository,
       _noteRepository = noteRepository,
       _cryptoService = cryptoService;

  final SecretRepository _secretRepository;
  final NoteRepository _noteRepository;
  final CryptoService _cryptoService;

  @override
  Future<List<ProjectedChatContextItem>> projectManual({
    required List<ChatContextItem> items,
    required SearchConfiguration configuration,
    required ChatContextProjectionTarget target,
  }) async {
    final projected = <ProjectedChatContextItem>[];
    for (final item in items) {
      final value = switch (item.type) {
        ChatContextItemType.secret => await _projectSecret(
          item.id,
          configuration: configuration,
          target: target,
        ),
        ChatContextItemType.note => await _projectNote(
          item.id,
          configuration: configuration,
        ),
      };
      if (value != null) {
        projected.add(value);
      }
    }
    return List<ProjectedChatContextItem>.unmodifiable(projected);
  }

  Future<ProjectedChatContextItem?> _projectSecret(
    String id, {
    required SearchConfiguration configuration,
    required ChatContextProjectionTarget target,
  }) async {
    final secret = await _secretRepository.getById(id);
    if (secret == null || secret.deletedAt != null) {
      return null;
    }

    final lines = <String>[];
    _addDecryptedField(
      lines,
      enabled: configuration.includeUsername,
      label: '用户名',
      item: secret,
      ciphertext: secret.usernameCiphertext,
      field: EncryptedDatabaseField.secretUsername,
    );
    _addDecryptedField(
      lines,
      enabled:
          target == ChatContextProjectionTarget.local &&
          configuration.includePasswordField,
      label: '密码',
      item: secret,
      ciphertext: secret.passwordCiphertext,
      field: EncryptedDatabaseField.secretPassword,
    );
    _addDecryptedField(
      lines,
      enabled: configuration.includeUrl,
      label: '网址',
      item: secret,
      ciphertext: secret.websiteUrlCiphertext,
      field: EncryptedDatabaseField.secretWebsiteUrl,
    );
    _addDecryptedField(
      lines,
      enabled: configuration.includeSecretNote,
      label: '备注',
      item: secret,
      ciphertext: secret.noteCiphertext,
      field: EncryptedDatabaseField.secretNote,
    );
    if (configuration.includeTags && secret.tags.isNotEmpty) {
      lines.add('标签：${secret.tags.join('、')}');
    }

    final title = configuration.includeTitle ? secret.title.trim() : '';
    if (title.isEmpty && lines.isEmpty) {
      return null;
    }
    return ProjectedChatContextItem(
      type: ChatContextItemType.secret,
      title: title,
      content: lines.join('\n'),
    );
  }

  Future<ProjectedChatContextItem?> _projectNote(
    String id, {
    required SearchConfiguration configuration,
  }) async {
    final note = await _noteRepository.getById(id);
    if (note == null || note.deletedAt != null) {
      return null;
    }

    final lines = <String>[];
    if (configuration.includeNoteBody) {
      final content = _cryptoService
          .decryptField(
            note.contentCiphertext,
            field: EncryptedDatabaseField.noteContent,
            rowId: note.id,
          )
          .trim();
      if (content.isNotEmpty) {
        lines.add('正文：$content');
      }
    }
    if (configuration.includeTags && note.tags.isNotEmpty) {
      lines.add('标签：${note.tags.join('、')}');
    }

    final title = configuration.includeTitle ? note.title.trim() : '';
    if (title.isEmpty && lines.isEmpty) {
      return null;
    }
    return ProjectedChatContextItem(
      type: ChatContextItemType.note,
      title: title,
      content: lines.join('\n'),
    );
  }

  void _addDecryptedField(
    List<String> lines, {
    required bool enabled,
    required String label,
    required SecretItem item,
    required List<int>? ciphertext,
    required EncryptedDatabaseField field,
  }) {
    if (!enabled) {
      return;
    }
    final plaintext = _cryptoService
        .decryptField(ciphertext, field: field, rowId: item.id)
        .trim();
    if (plaintext.isNotEmpty) {
      lines.add('$label：$plaintext');
    }
  }
}

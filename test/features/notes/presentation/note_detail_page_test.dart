import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/presentation/note_detail_page.dart';

class _FakeCryptoService implements CryptoService {
  const _FakeCryptoService();

  @override
  String decryptNullable(List<int>? ciphertext) {
    if (ciphertext == null) {
      return '';
    }
    return String.fromCharCodes(ciphertext);
  }

  @override
  List<int>? encryptNullable(String? plaintext) => plaintext?.codeUnits;
}

NoteItem _fakeNote() {
  return NoteItem(
    id: 'note-1',
    vaultId: 'vault-1',
    title: 'Recovery Note',
    contentCiphertext: 'backup codes'.codeUnits,
    summaryCacheCiphertext: 'summary'.codeUnits,
    tags: const ['backup'],
    categoryId: null,
    favorite: false,
    createdAt: DateTime(2026, 1, 2),
    updatedAt: DateTime(2026, 1, 2),
  );
}

void main() {
  testWidgets('NoteDetailPage shows enhanced search handoff card when opened from search', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith((ref) async => _fakeNote()),
        ],
        child: const MaterialApp(
          home: NoteDetailPage(
            noteId: 'note-1',
            searchQuery: 'Recovery Note',
            searchSource: 'keyword',
            searchContext: '标题：Recovery Note',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('来自搜索'), findsOneWidget);
    expect(find.text('命中方式：关键词优先'), findsOneWidget);
    expect(find.text('查询词：Recovery Note'), findsOneWidget);
    expect(find.text('命中说明：本次命中主要落在标题字段。'), findsOneWidget);
    expect(find.text('优先查看：标题，这是当前最直接的命中位置。'), findsOneWidget);
  });

  testWidgets('NoteDetailPage shows unified semantic-hit label for semantic search entry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith((ref) async => _fakeNote()),
        ],
        child: const MaterialApp(
          home: NoteDetailPage(
            noteId: 'note-1',
            searchQuery: 'Recovery Note',
            searchSource: 'semantic',
            searchContext: '摘要：恢复码备忘',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('命中方式：语义命中'), findsOneWidget);
    expect(find.text('命中说明：本次命中主要落在摘要字段。'), findsOneWidget);
    expect(find.text('优先查看：摘要，先确认概要是否对应本次查询。'), findsOneWidget);
  });

  testWidgets('NoteDetailPage shows content-focused guidance when search context targets content', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith((ref) async => _fakeNote()),
        ],
        child: const MaterialApp(
          home: NoteDetailPage(
            noteId: 'note-1',
            searchSource: 'semantic',
            searchContext: '正文：backup codes',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('优先查看：正文内容，这里最可能包含本次命中上下文。'), findsOneWidget);
  });

  testWidgets('NoteDetailPage shows semantic-only handoff explanation for retained semantic result', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith((ref) async => _fakeNote()),
        ],
        child: const MaterialApp(
          home: NoteDetailPage(
            noteId: 'note-1',
            searchSource: 'semantic',
            searchContext: '正文：backup codes',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('承接说明：该结果以语义命中进入详情页，建议结合命中字段与正文继续确认。'), findsOneWidget);
  });

  testWidgets('NoteDetailPage hides search handoff card when opened directly', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith((ref) async => _fakeNote()),
        ],
        child: const MaterialApp(
          home: NoteDetailPage(noteId: 'note-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('来自搜索'), findsNothing);
  });

  testWidgets('NoteDetailPage highlights summary block when search context targets summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith((ref) async => _fakeNote()),
        ],
        child: const MaterialApp(
          home: NoteDetailPage(
            noteId: 'note-1',
            searchSource: 'semantic',
            searchContext: '摘要：summary',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-hit-summary')), findsOneWidget);
  });

  testWidgets('NoteDetailPage highlights content block when search context targets content', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith((ref) async => _fakeNote()),
        ],
        child: const MaterialApp(
          home: NoteDetailPage(
            noteId: 'note-1',
            searchSource: 'semantic',
            searchContext: '正文：backup codes',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-hit-content')), findsOneWidget);
  });

  testWidgets('NoteDetailPage does not highlight any block for unknown search context', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith((ref) async => _fakeNote()),
        ],
        child: const MaterialApp(
          home: NoteDetailPage(
            noteId: 'note-1',
            searchSource: 'semantic',
            searchContext: '未知：summary',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-hit-title')), findsNothing);
    expect(find.byKey(const ValueKey('note-hit-summary')), findsNothing);
    expect(find.byKey(const ValueKey('note-hit-tags')), findsNothing);
    expect(find.byKey(const ValueKey('note-hit-content')), findsNothing);
    expect(find.textContaining('优先查看：'), findsNothing);
  });
}

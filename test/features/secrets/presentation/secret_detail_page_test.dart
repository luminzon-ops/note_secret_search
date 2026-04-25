import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_detail_page.dart';

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

SecretItem _fakeSecret() {
  return SecretItem(
    id: 'secret-1',
    vaultId: 'vault-1',
    title: 'Bank Account',
    usernameCiphertext: 'alice@example.com'.codeUnits,
    passwordCiphertext: 'secret-pass'.codeUnits,
    websiteUrlCiphertext: 'bank.example.com'.codeUnits,
    noteCiphertext: 'bank note'.codeUnits,
    tags: const ['finance'],
    categoryId: null,
    favorite: false,
    createdAt: DateTime(2026, 1, 2),
    updatedAt: DateTime(2026, 1, 2),
  );
}

void main() {
  testWidgets('SecretDetailPage shows enhanced search handoff card when opened from search', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          secretDetailProvider('secret-1').overrideWith((ref) async => _fakeSecret()),
        ],
        child: const MaterialApp(
          home: SecretDetailPage(
            secretId: 'secret-1',
            searchQuery: 'Bank Account',
            searchSource: 'keyword_semantic',
            searchContext: '标题：Bank Account',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('来自搜索'), findsOneWidget);
    expect(find.text('命中方式：双命中'), findsOneWidget);
    expect(find.text('查询词：Bank Account'), findsOneWidget);
    expect(find.text('命中说明：本次命中主要落在标题字段。'), findsOneWidget);
    expect(find.text('优先查看：标题，这是当前最直接的命中位置。'), findsOneWidget);
  });

  testWidgets('SecretDetailPage shows note-focused guidance when search context targets note', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          secretDetailProvider('secret-1').overrideWith((ref) async => _fakeSecret()),
        ],
        child: const MaterialApp(
          home: SecretDetailPage(
            secretId: 'secret-1',
            searchSource: 'semantic',
            searchContext: '备注：bank note',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('优先查看：备注字段，查看补充说明是否匹配查询意图。'), findsOneWidget);
  });

  testWidgets('SecretDetailPage shows semantic-only handoff explanation for retained semantic result', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          secretDetailProvider('secret-1').overrideWith((ref) async => _fakeSecret()),
        ],
        child: const MaterialApp(
          home: SecretDetailPage(
            secretId: 'secret-1',
            searchSource: 'semantic',
            searchContext: '备注：bank note',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('承接说明：该结果以语义命中进入详情页，建议结合命中字段与正文继续确认。'), findsOneWidget);
  });

  testWidgets('SecretDetailPage hides search handoff card when opened directly', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          secretDetailProvider('secret-1').overrideWith((ref) async => _fakeSecret()),
        ],
        child: const MaterialApp(
          home: SecretDetailPage(secretId: 'secret-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('来自搜索'), findsNothing);
  });

  testWidgets('SecretDetailPage highlights username row when search context targets account', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          secretDetailProvider('secret-1').overrideWith((ref) async => _fakeSecret()),
        ],
        child: const MaterialApp(
          home: SecretDetailPage(
            secretId: 'secret-1',
            searchSource: 'semantic',
            searchContext: '账号：alice@example.com',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('secret-hit-username')), findsOneWidget);
  });

  testWidgets('SecretDetailPage highlights note row when search context targets note', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          secretDetailProvider('secret-1').overrideWith((ref) async => _fakeSecret()),
        ],
        child: const MaterialApp(
          home: SecretDetailPage(
            secretId: 'secret-1',
            searchSource: 'semantic',
            searchContext: '备注：bank note',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('secret-hit-note')), findsOneWidget);
  });

  testWidgets('SecretDetailPage does not highlight any row for unknown search context', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          secretDetailProvider('secret-1').overrideWith((ref) async => _fakeSecret()),
        ],
        child: const MaterialApp(
          home: SecretDetailPage(
            secretId: 'secret-1',
            searchSource: 'semantic',
            searchContext: '未知：bank note',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('secret-hit-title')), findsNothing);
    expect(find.byKey(const ValueKey('secret-hit-username')), findsNothing);
    expect(find.byKey(const ValueKey('secret-hit-website')), findsNothing);
    expect(find.byKey(const ValueKey('secret-hit-tags')), findsNothing);
    expect(find.byKey(const ValueKey('secret-hit-note')), findsNothing);
  });
}

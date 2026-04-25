# Detail Search Explanation Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 SecretDetailPage 与 NoteDetailPage 在从搜索进入时，用与列表页一致的命中类型文案轻量承接搜索解释。

**Architecture:** 保持详情页现有顶部来源说明区块结构，只对文案映射与显示行为做最小增强。继续复用已存在的 `searchQuery`、`searchSource`、`searchContext` 参数，不新增复杂状态或 explain panel。

**Tech Stack:** Flutter, Riverpod, flutter_test

---

## File Structure

- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
  - 对齐搜索来源命中类型文案
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
  - 对齐搜索来源命中类型文案
- Modify: `test/features/search/presentation/search_page_test.dart`
  - 继续保留从 SearchPage 导航到详情页的连续性测试
- Create or Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
  - 补 SecretDetailPage 的直接页面测试
- Create or Modify: `test/features/notes/presentation/note_detail_page_test.dart`
  - 补 NoteDetailPage 的直接页面测试

### Task 1: SecretDetailPage 轻量承接

**Files:**
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Test: `test/features/secrets/presentation/secret_detail_page_test.dart`

- [ ] **Step 1: Write the failing widget test for search entry handoff**

```dart
testWidgets('SecretDetailPage shows search handoff card with dual-hit label', (tester) async {
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

  expect(find.text('来自搜索 · 双命中'), findsOneWidget);
  expect(find.text('查询词：Bank Account'), findsOneWidget);
  expect(find.text('命中上下文：标题：Bank Account'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart --plain-name "SecretDetailPage shows search handoff card with dual-hit label"`

Expected: FAIL because the page still renders the old label mapping.

- [ ] **Step 3: Write the failing widget test for non-search entry**

```dart
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
```

- [ ] **Step 4: Run test to verify it fails or confirms baseline**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart --plain-name "SecretDetailPage hides search handoff card when opened directly"`

Expected: PASS or FAIL depending on baseline; if already green, keep it as regression coverage.

- [ ] **Step 5: Write minimal implementation**

```dart
String _searchSourceLabel(String? source) {
  switch (source) {
    case 'keyword_semantic':
      return '双命中';
    case 'semantic':
      return '语义辅助';
    case 'keyword':
    default:
      return '关键词优先';
  }
}
```

- [ ] **Step 6: Run targeted tests to verify they pass**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`

Expected: PASS

### Task 2: NoteDetailPage 轻量承接

**Files:**
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
- Test: `test/features/notes/presentation/note_detail_page_test.dart`

- [ ] **Step 1: Write the failing widget test for search entry handoff**

```dart
testWidgets('NoteDetailPage shows search handoff card with keyword-primary label', (tester) async {
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

  expect(find.text('来自搜索 · 关键词优先'), findsOneWidget);
  expect(find.text('查询词：Recovery Note'), findsOneWidget);
  expect(find.text('命中上下文：标题：Recovery Note'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart --plain-name "NoteDetailPage shows search handoff card with keyword-primary label"`

Expected: FAIL because the page still renders the old label mapping.

- [ ] **Step 3: Write the failing widget test for semantic-assist label**

```dart
testWidgets('NoteDetailPage shows semantic-assist label for semantic search entry', (tester) async {
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

  expect(find.text('来自搜索 · 语义辅助'), findsOneWidget);
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart --plain-name "NoteDetailPage shows semantic-assist label for semantic search entry"`

Expected: FAIL because semantic label mapping is not updated yet.

- [ ] **Step 5: Write minimal implementation**

```dart
String _searchSourceLabel(String? source) {
  switch (source) {
    case 'keyword_semantic':
      return '双命中';
    case 'semantic':
      return '语义辅助';
    case 'keyword':
    default:
      return '关键词优先';
  }
}
```

- [ ] **Step 6: Run targeted tests to verify they pass**

Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: PASS

### Task 3: SearchPage continuity regression + full verification

**Files:**
- Modify: `test/features/search/presentation/search_page_test.dart`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Update existing SearchPage navigation continuity assertions if needed**

Expected assertions:

```dart
expect(find.text('来自搜索 · 双命中'), findsOneWidget);
```

```dart
expect(find.text('来自搜索 · 关键词优先'), findsOneWidget);
```

- [ ] **Step 2: Run related test files**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`

Expected: PASS

Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: PASS

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS

- [ ] **Step 3: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/secrets/presentation/secret_detail_page.dart`
- `lib/features/notes/presentation/note_detail_page.dart`
- `test/features/secrets/presentation/secret_detail_page_test.dart`
- `test/features/notes/presentation/note_detail_page_test.dart`
- `test/features/search/presentation/search_page_test.dart`

Expected: clean diagnostics

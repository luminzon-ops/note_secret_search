# Search Explanation Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the explanation hierarchy between result-card ranking reasons and detail-page hit guidance through shared field-level helpers.

**Architecture:** Extract shared field-explanation helpers into `detail_search_hit_target.dart`, then have both SearchPage and detail pages consume them. Keep the change presentation-only and avoid changing routing or search logic.

**Tech Stack:** Flutter, Dart, flutter_test

---

### Task 1: Add shared field-guidance helper coverage

**Files:**
- Modify: `test/features/search/presentation/detail_search_hit_target_test.dart`
- Modify: `lib/features/search/presentation/detail_search_hit_target.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(resolveSecretDetailSearchFocusHint('账号：alice@example.com'), '账号字段，这里最可能承载本次命中。');
expect(resolveNoteDetailSearchFocusHint('正文：backup codes'), '正文内容，这里最可能包含本次命中上下文。');
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/detail_search_hit_target_test.dart`
Expected: FAIL because the shared helpers do not exist yet

- [ ] **Step 3: Write minimal implementation**

```dart
String? resolveSecretDetailSearchFocusHint(String? searchContext) { ... }
String? resolveNoteDetailSearchFocusHint(String? searchContext) { ... }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/search/presentation/detail_search_hit_target_test.dart`
Expected: PASS

### Task 2: Move detail pages to shared guidance helpers

**Files:**
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(find.text('优先查看：备注字段，查看补充说明是否匹配查询意图。'), findsOneWidget);
expect(find.text('优先查看：正文内容，这里最可能包含本次命中上下文。'), findsOneWidget);
```

Add assertions that still pass through shared helpers, not page-local conditionals.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`
Expected: FAIL after removing local helpers before replacement

- [ ] **Step 3: Write minimal implementation**

```dart
final searchFocusHint = resolveSecretDetailSearchFocusHint(searchContext);
final searchFocusHint = resolveNoteDetailSearchFocusHint(searchContext);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`
Expected: PASS

### Task 3: Align SearchPage ranking reasons to shared field guidance

**Files:**
- Modify: `test/features/search/presentation/search_page_test.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `lib/features/search/presentation/detail_search_hit_target.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(find.text('• 优先查看标题，这是当前最直接的命中位置。'), findsOneWidget);
expect(find.text('• 优先查看标签字段，确认标签线索是否匹配。'), findsOneWidget);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart`
Expected: FAIL because SearchPage still uses old `强信号 / 辅助信号` field phrases

- [ ] **Step 3: Write minimal implementation**

```dart
final focusReason = resolveSemanticFieldFocusHint(item.semanticHitField);
if (focusReason != null) lines.add('优先查看$focusReason');
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/search/presentation/search_page_test.dart`
Expected: PASS

### Task 4: Final verification

**Files:**
- Verify: `lib/features/search/presentation/detail_search_hit_target.dart`
- Verify: `lib/features/search/presentation/search_page.dart`
- Verify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Verify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Run targeted tests**

```bash
flutter test test/features/search/presentation/detail_search_hit_target_test.dart
flutter test test/features/search/presentation/search_page_test.dart
flutter test test/features/secrets/presentation/secret_detail_page_test.dart
flutter test test/features/notes/presentation/note_detail_page_test.dart
```

- [ ] **Step 2: Run analyzer**

```bash
flutter analyze
```

- [ ] **Step 3: Summarize next pivot**

Document that the next likely task is unifying `命中说明` sentence templates with the `语义命中` block itself.

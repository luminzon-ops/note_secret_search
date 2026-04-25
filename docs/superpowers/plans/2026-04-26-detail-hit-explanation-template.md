# Detail Hit Explanation Template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace raw detail-page hit-context echoes with shared, productized hit-explanation sentence templates while preserving fallback behavior.

**Architecture:** Add a shared hit-explanation helper beside the existing hit-target/focus helpers in `detail_search_hit_target.dart`, then switch both detail pages to render template text when a known field is recognized. Keep unknown contexts as raw fallback.

**Tech Stack:** Flutter, Dart, flutter_test

---

### Task 1: Add shared hit-explanation helper coverage

**Files:**
- Modify: `test/features/search/presentation/detail_search_hit_target_test.dart`
- Modify: `lib/features/search/presentation/detail_search_hit_target.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(resolveSecretDetailHitExplanation('标题：Bank Account'), '本次命中主要落在标题字段。');
expect(resolveNoteDetailHitExplanation('正文：backup codes'), '本次命中主要落在正文内容。');
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/detail_search_hit_target_test.dart`
Expected: FAIL because the helper does not exist yet

- [ ] **Step 3: Write minimal implementation**

```dart
String? resolveSecretDetailHitExplanation(String? searchContext) { ... }
String? resolveNoteDetailHitExplanation(String? searchContext) { ... }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/search/presentation/detail_search_hit_target_test.dart`
Expected: PASS

### Task 2: Switch detail pages to template explanations

**Files:**
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(find.text('命中说明：本次命中主要落在标题字段。'), findsOneWidget);
expect(find.text('命中说明：本次命中主要落在摘要字段。'), findsOneWidget);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`
Expected: FAIL because detail pages still render raw `标题：.../摘要：...`

- [ ] **Step 3: Write minimal implementation**

```dart
final hitExplanation = resolveSecretDetailHitExplanation(searchContext) ?? searchContext;
Text('命中说明：$hitExplanation')
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`
Expected: PASS

### Task 3: Preserve fallback behavior for unknown contexts

**Files:**
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(find.text('命中说明：未知：bank note'), findsOneWidget);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`
Expected: FAIL if implementation dropped raw-context fallback

- [ ] **Step 3: Write minimal implementation**

```dart
final hitExplanation = resolveSecretDetailHitExplanation(searchContext) ?? searchContext;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`
Expected: PASS

### Task 4: Final verification

**Files:**
- Verify: `lib/features/search/presentation/detail_search_hit_target.dart`
- Verify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Verify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Run targeted tests**

```bash
flutter test test/features/search/presentation/detail_search_hit_target_test.dart
flutter test test/features/secrets/presentation/secret_detail_page_test.dart
flutter test test/features/notes/presentation/note_detail_page_test.dart
```

- [ ] **Step 2: Run analyzer**

```bash
flutter analyze
```

- [ ] **Step 3: Summarize next pivot**

Document that the next likely task is field-level retained-reason explanation for semantic-only detail handoff.

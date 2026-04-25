# Search Copy Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify semantic-search explanation wording across result cards, observability summaries, and detail-page handoff in consistent product-facing Chinese.

**Architecture:** Keep the change presentation-only. Reuse existing explanation helpers in `search_result_explanation.dart`, then update `search_page.dart` and both detail pages to consume the same wording so list/detail terminology stays aligned.

**Tech Stack:** Flutter, Dart, flutter_test

---

### Task 1: Update explanation helper expectations first

**Files:**
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `lib/features/search/presentation/search_result_explanation.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(explanation, '这条结果同时命中关键词与重点语义字段，可优先查看。');
expect(summary.hitBreakdown, '命中结构：双命中 1 条，关键词优先 1 条，语义命中 1 条。');
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`
Expected: FAIL because old copy still contains `高质量语义命中` / `语义辅助` / `semantic-only`

- [ ] **Step 3: Write minimal implementation**

```dart
return '这条结果同时命中关键词与重点语义字段，可优先查看。';
return '命中结构：双命中 $dualCount 条，关键词优先 $keywordPrimaryCount 条，语义命中 $semanticAssistCount 条。';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`
Expected: PASS

### Task 2: Update SearchPage widget copy

**Files:**
- Modify: `test/features/search/presentation/search_page_test.dart`
- Modify: `lib/features/search/presentation/search_page.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(find.text('语义命中'), findsWidgets);
expect(find.text('这条结果主要由重点语义命中支持，适合优先检查。'), findsOneWidget);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart`
Expected: FAIL because chips and observability text still use old wording

- [ ] **Step 3: Write minimal implementation**

```dart
label: Text(resolveSearchResultHitLabel(item)),
Text(summary.hitBreakdown),
```

Update helper-driven strings only; do not change layout.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/search/presentation/search_page_test.dart`
Expected: PASS

### Task 3: Update detail-page handoff wording

**Files:**
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Write the failing test**

```dart
expect(find.text('承接说明：该结果以语义命中进入详情页，建议结合命中字段与正文继续确认。'), findsOneWidget);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`
Expected: FAIL because old handoff copy still says `保留的语义命中`

- [ ] **Step 3: Write minimal implementation**

```dart
return '该结果以语义命中进入详情页，建议结合命中字段与正文继续确认。';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`
Expected: PASS

### Task 4: Final verification

**Files:**
- Verify: `lib/features/search/presentation/search_result_explanation.dart`
- Verify: `lib/features/search/presentation/search_page.dart`
- Verify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Verify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Run targeted presentation tests**

```bash
flutter test test/features/search/presentation/search_result_explanation_test.dart
flutter test test/features/search/presentation/search_page_test.dart
flutter test test/features/secrets/presentation/secret_detail_page_test.dart
flutter test test/features/notes/presentation/note_detail_page_test.dart
```

- [ ] **Step 2: Run analyzer**

```bash
flutter analyze
```

- [ ] **Step 3: Summarize next pivot**

Document that the next likely task is unifying `排序依据` / `字段提示` copy with the same terminology.

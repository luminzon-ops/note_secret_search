# Chat And Model Layout Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the model-management source layout overflow, convert AI chat recent sessions into a responsive phone drawer / wide-screen sidebar, and make model download state changes feel immediate before continuing Huawei real-device verification.

**Architecture:** Keep the current Riverpod/repository/runtime business flow intact and refactor only the presentation layer plus a small display-oriented status mapping helper. The model page will split source/status/actions into clearer sections inside the existing tile flow, while the chat page will branch layout by screen width without changing session persistence or router structure.

**Tech Stack:** Flutter, Dart, Riverpod, Material 3 widgets, existing model download providers, existing chat session providers, Flutter widget tests, provider tests, `flutter analyze`, Huawei Android real-device smoke via adb.

---

## File Structure / Responsibilities

### Existing files to modify

- `lib/features/ai_models/presentation/model_management_page.dart`
  - Refactor the catalog tile layout so current source, trust copy, download status, and actions are sectioned cleanly and no longer rely on the problematic horizontal source row.

- `lib/features/ai_chat/presentation/ai_chat_page.dart`
  - Add responsive layout branching so phone widths use a drawer and wide widths keep a persistent sidebar.

- `test/features/ai_models/presentation/model_management_page_test.dart`
  - Add widget coverage for stacked source layout, source selector visibility, and immediate status copy rendering.

- `test/features/ai_chat/presentation/ai_chat_page_test.dart`
  - Add widget coverage for hamburger/drawer behavior on phone widths and persistent sidebar behavior on wide widths.

- `test/features/ai_models/application/model_download_providers_test.dart`
  - Add provider/presentation-state coverage for immediate task-state transitions and stage mapping behavior.

### New files to create

- `lib/features/ai_models/presentation/model_download_status_view_model.dart`
  - Provide a small, display-oriented mapping layer that translates raw `ModelDownloadTask` + install/runtime evidence into user-visible stages such as `连接中`, `下载中`, `校验中`, and `失败`.

- `test/features/ai_models/presentation/model_download_status_view_model_test.dart`
  - Add focused unit tests for the new status mapping helper so UI assertions do not need to encode the mapping logic repeatedly.

### Existing files to validate but not structurally redesign

- `lib/features/ai_models/application/model_download_providers.dart`
  - Verify the current downloader/task persistence flow remains the backend truth and only expose more immediate display feedback on top.

- `lib/features/ai_chat/application/chat_session_providers.dart`
  - Keep current session selection and refresh logic unchanged while reusing it from the new drawer/sidebar containers.

---

## Task 1: Add failing tests for model source layout and tighter section rendering

**Files:**
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`

- [ ] **Step 1: Add a reusable multi-source embedding catalog entry fixture**

Add this helper near the other catalog fixtures in `test/features/ai_models/presentation/model_management_page_test.dart`:

```dart
const _bgeEmbeddingCatalogEntry = ModelCatalogEntry(
  id: 'bge-small-zh',
  type: 'embedding',
  tier: 'mvp',
  displayName: 'BGE Small 中文 Embedding',
  description: '用于本地中文语义检索的 BGE 小型 embedding 模型。',
  sizeBytes: 10485760,
  minRamMb: 512,
  recommendedTier: 'mvp',
  sources: <ModelSourceEntry>[
    ModelSourceEntry(
      id: 'hf-xenova-pinned',
      label: 'HuggingFace Xenova（revision pinned）',
      url: 'https://huggingface.co/Xenova/bge-small-zh-v1.5/resolve/75c43b069aac4d136ba6bc1122f995fedcfd2781/onnx/model.onnx',
      checksum: 'sha256:abc',
      signature: 'signed',
      trustMode: 'signed',
    ),
    ModelSourceEntry(
      id: 'hf-xenova-main',
      label: 'HuggingFace Xenova（main fallback）',
      url: 'https://huggingface.co/Xenova/bge-small-zh-v1.5/resolve/main/onnx/model.onnx',
      checksum: 'sha256:def',
    ),
  ],
);
```

- [ ] **Step 2: Write the failing widget test for a stacked current-source section**

Add this test to `test/features/ai_models/presentation/model_management_page_test.dart`:

```dart
testWidgets('ModelManagementPage renders current source and selector in separate vertical sections', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelCatalogEntriesProvider.overrideWith((ref) async => const [_bgeEmbeddingCatalogEntry]),
        modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
        modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
        embeddingRuntimeStatesProvider.overrideWith(
          (ref) async => const <String, EmbeddingEngineState>{},
        ),
        modelDownloadControllerProvider.overrideWith(
          (ref) => _FakeModelDownloadController(ref: ref),
        ),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('当前下载源'), findsOneWidget);
  expect(find.textContaining('HuggingFace Xenova（revision pinned）'), findsOneWidget);
  expect(find.byType(DropdownButton<String>), findsOneWidget);
});
```

- [ ] **Step 3: Run the targeted test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage renders current source and selector in separate vertical sections"
```

Expected:

- The test fails because the current production UI still renders `当前下载源：...` inline inside one horizontal `Row` and does not expose a standalone `Text('当前下载源')` section header.

- [ ] **Step 4: Write the failing widget test for compact download status copy instead of the old placeholder text**

Add this test to the same file:

```dart
testWidgets('ModelManagementPage shows active download status section with compact staged copy', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelCatalogEntriesProvider.overrideWith((ref) async => const [_bgeEmbeddingCatalogEntry]),
        modelDownloadTasksProvider.overrideWith(
          (ref) async => [
            ModelDownloadTask(
              id: 'task-1',
              modelId: 'bge-small-zh',
              sourceId: 'hf-xenova-pinned',
              status: ModelDownloadStatus.downloading,
              totalBytes: 10485760,
              downloadedBytes: 0,
              averageSpeed: null,
              errorMessage: null,
              resumable: true,
              createdAt: DateTime(2026, 5, 2, 10, 0, 0),
              updatedAt: DateTime(2026, 5, 2, 10, 0, 1),
            ),
          ],
        ),
        modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
        embeddingRuntimeStatesProvider.overrideWith(
          (ref) async => const <String, EmbeddingEngineState>{},
        ),
        modelDownloadControllerProvider.overrideWith(
          (ref) => _FakeModelDownloadController(ref: ref),
        ),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('下载状态'), findsOneWidget);
  expect(find.textContaining('连接中'), findsOneWidget);
  expect(find.textContaining('已下载 0 MB / 10 MB'), findsOneWidget);
});
```

- [ ] **Step 5: Run the targeted test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows active download status section with compact staged copy"
```

Expected:

- The test fails because the current UI does not render a `下载状态` section header and still uses the old `_DownloadStatusCard` wording directly.

- [ ] **Step 6: Commit**

```bash
git add test/features/ai_models/presentation/model_management_page_test.dart
git commit -m "test: add model page layout regression coverage"
```

---

## Task 2: Implement the model page section refactor and stacked source layout

**Files:**
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Replace the current source `Row` with a vertical source section**

In `lib/features/ai_models/presentation/model_management_page.dart`, replace the existing block at `574-627` with this structure:

```dart
if (entry.sources.isNotEmpty) ...[
  _ModelSourceSection(
    selectedSourceId: _selectedSourceId,
    selectedSource: selectedSource,
    effectiveSource: effectiveSource,
    entry: entry,
    onChanged: (value) {
      if (value == null) {
        return;
      }
      setState(() {
        _selectedSourceId = value;
      });
    },
  ),
  const SizedBox(height: 12),
],
```

- [ ] **Step 2: Add a dedicated `_ModelSourceSection` widget below `_CatalogEntryTileState`**

Add this widget to the same file:

```dart
class _ModelSourceSection extends StatelessWidget {
  const _ModelSourceSection({
    required this.selectedSourceId,
    required this.selectedSource,
    required this.effectiveSource,
    required this.entry,
    required this.onChanged,
  });

  final String? selectedSourceId;
  final ModelSourceEntry? selectedSource;
  final ModelSourceEntry? effectiveSource;
  final ModelCatalogEntry entry;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final helperColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('当前下载源', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(
          effectiveSource != null ? formatSourceLabelWithTrust(effectiveSource!) : '未选择',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (entry.sources.length > 1) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedSource?.id,
            isExpanded: true,
            items: [
              for (final source in entry.sources)
                DropdownMenuItem<String>(
                  value: source.id,
                  child: Text(formatSourceLabelWithTrust(source)),
                ),
            ],
            onChanged: onChanged,
            decoration: const InputDecoration(
              labelText: '切换下载源',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
        if (effectiveSource != null && formatEffectiveSourceTrustCaption(effectiveSource!) != null) ...[
          const SizedBox(height: 8),
          Text(
            formatEffectiveSourceTrustCaption(effectiveSource!)!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: helperColor),
          ),
        ],
        if (shouldShowGenericTrustExplainer(entry.sources)) ...[
          const SizedBox(height: 4),
          Text(
            formatGenericTrustExplainer(entry.sources)!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: helperColor),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 3: Replace the current `_DownloadStatusCard` title block with a sectioned header**

Update the start of `_DownloadStatusCard.build` in the same file so the active-task state begins like this:

```dart
return Card(
  margin: EdgeInsets.zero,
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('下载状态', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.download_for_offline_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(_displayStageLabel(task!))),
          ],
        ),
        const SizedBox(height: 8),
        if (sourceLabel != null && sourceLabel!.isNotEmpty)
          Text('当前来源：$sourceLabel'),
        const SizedBox(height: 8),
        if (task!.progress != null)
          LinearProgressIndicator(value: task!.progress)
        else
          const LinearProgressIndicator(),
```

- [ ] **Step 4: Add a temporary stage-label helper that will be backed by the new view-model file in a later task**

Add this helper inside `_DownloadStatusCard` for now:

```dart
String _displayStageLabel(ModelDownloadTask task) {
  if (task.status == ModelDownloadStatus.failed) {
    return '失败';
  }
  if (task.status == ModelDownloadStatus.completed) {
    return '已完成';
  }
  if (task.status == ModelDownloadStatus.paused) {
    return '已暂停';
  }
  if (task.status == ModelDownloadStatus.downloading && task.downloadedBytes == 0) {
    return '连接中';
  }
  if (task.status == ModelDownloadStatus.downloading) {
    return '下载中';
  }
  if (task.status == ModelDownloadStatus.queued) {
    return '已发起';
  }
  return '未开始';
}
```

- [ ] **Step 5: Run the model page widget test file to verify green**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected:

- All model-management widget tests pass, including the two new layout/status regression tests.

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_models/presentation/model_management_page.dart test/features/ai_models/presentation/model_management_page_test.dart
git commit -m "feat: refactor model page source and status sections"
```

---

## Task 3: Add failing responsive layout tests for AI chat phone drawer and wide sidebar

**Files:**
- Modify: `test/features/ai_chat/presentation/ai_chat_page_test.dart`
- Modify: `lib/features/ai_chat/presentation/ai_chat_page.dart`

- [ ] **Step 1: Add a helper to pump the chat route at a specific logical size**

Add this helper near the existing `buildContainer` helper in `test/features/ai_chat/presentation/ai_chat_page_test.dart`:

```dart
Future<void> pumpChatRouteAtSize(
  WidgetTester tester,
  ProviderContainer container, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = container.read(appRouterProvider);
  router.go('/ai/chat');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2: Write the failing phone-width drawer test**

Add this test to `test/features/ai_chat/presentation/ai_chat_page_test.dart`:

```dart
testWidgets('AI chat page uses drawer-based recent sessions on phone widths', (tester) async {
  final container = await buildContainer(
    chatRepository: _FakeChatSessionRepository(
      sessions: [
        ChatSession(
          id: 'session-1',
          mode: ChatMode.privateQa,
          title: '邮箱问答',
          allowPrivateContext: true,
          archived: false,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
        ),
      ],
    ),
  );

  addTearDown(container.dispose);

  await pumpChatRouteAtSize(tester, container, size: const Size(393, 852));

  expect(find.text('最近会话'), findsNothing);
  expect(find.byTooltip('打开最近会话'), findsOneWidget);

  await tester.tap(find.byTooltip('打开最近会话'));
  await tester.pumpAndSettle();

  expect(find.text('最近会话'), findsOneWidget);
  expect(find.text('邮箱问答'), findsOneWidget);
});
```

- [ ] **Step 3: Run the targeted test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart --plain-name "AI chat page uses drawer-based recent sessions on phone widths"
```

Expected:

- The test fails because the current implementation always renders the fixed 240 px left rail and has no hamburger button.

- [ ] **Step 4: Write the failing wide-layout persistence test**

Add this test to the same file:

```dart
testWidgets('AI chat page keeps persistent recent sessions sidebar on wide widths', (tester) async {
  final container = await buildContainer(
    chatRepository: _FakeChatSessionRepository(
      sessions: [
        ChatSession(
          id: 'session-1',
          mode: ChatMode.privateQa,
          title: '邮箱问答',
          allowPrivateContext: true,
          archived: false,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
        ),
      ],
    ),
  );

  addTearDown(container.dispose);

  await pumpChatRouteAtSize(tester, container, size: const Size(1280, 800));

  expect(find.text('最近会话'), findsOneWidget);
  expect(find.byTooltip('打开最近会话'), findsNothing);
});
```

- [ ] **Step 5: Run the targeted test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart --plain-name "AI chat page keeps persistent recent sessions sidebar on wide widths"
```

Expected:

- The test initially fails if the phone/wide differentiation logic does not exist yet.

- [ ] **Step 6: Commit**

```bash
git add test/features/ai_chat/presentation/ai_chat_page_test.dart
git commit -m "test: add responsive ai chat layout coverage"
```

---

## Task 4: Implement responsive AI chat layout with phone drawer and wide sidebar

**Files:**
- Modify: `lib/features/ai_chat/presentation/ai_chat_page.dart`
- Modify: `test/features/ai_chat/presentation/ai_chat_page_test.dart`

- [ ] **Step 1: Add a width-mode helper in `AiChatPage`**

Inside `AiChatPage.build`, derive a phone-layout flag like this:

```dart
final isPhoneLayout = MediaQuery.sizeOf(context).width < 840;
```

Place it near the current provider reads so the layout branch can use it consistently.

- [ ] **Step 2: Add a `ScaffoldState` key and conditional app-bar leading button**

Update the top scaffold in `AiChatPage` to use a key and conditional leading icon:

```dart
final scaffoldKey = GlobalKey<ScaffoldState>();

return DefaultTabController(
  length: 2,
  child: Scaffold(
    key: scaffoldKey,
    appBar: AppBar(
      leading: isPhoneLayout
          ? IconButton(
              tooltip: '打开最近会话',
              icon: const Icon(Icons.menu),
              onPressed: () => scaffoldKey.currentState?.openDrawer(),
            )
          : null,
      title: const Text('AI 问答'),
      bottom: const TabBar(
        tabs: [
          Tab(text: '私密内容问答'),
          Tab(text: '自由聊天'),
        ],
      ),
    ),
```

- [ ] **Step 3: Add drawer wiring for phone layout**

Still in the same scaffold, add a conditional drawer:

```dart
drawer: isPhoneLayout
    ? Drawer(
        child: SafeArea(
          child: sessionsAsync.when(
            data: (sessions) => _SessionListPanel(
              sessions: sessions,
              currentSessionId: currentSessionId,
              closeAfterSelect: true,
            ),
            loading: () => const _SessionListPanelLoading(),
            error: (error, stackTrace) => Center(child: Text(error.toString())),
          ),
        ),
      )
    : null,
```

- [ ] **Step 4: Replace the current unconditional `Row` body with a responsive branch**

Replace the body branch in `AiChatPage` with this shape:

```dart
data: (externalStatus) {
  final mainContent = Column(
    children: [
      currentSessionAsync.when(
        data: (session) {
          final targetIndex = switch (session?.mode) {
            ChatMode.freeChat => 1,
            _ => 0,
          };
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final controller = DefaultTabController.maybeOf(context);
            if (controller != null && controller.index != targetIndex) {
              controller.animateTo(targetIndex);
            }
          });
          return const SizedBox.shrink();
        },
        loading: () => const SizedBox.shrink(),
        error: (error, stackTrace) => const SizedBox.shrink(),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: ChatRuntimeBanner(
          readiness: readiness,
          externalStatus: externalStatus,
        ),
      ),
      const Expanded(
        child: TabBarView(
          children: [
            PrivateQaTab(),
            FreeChatTab(),
          ],
        ),
      ),
    ],
  );

  if (isPhoneLayout) {
    return mainContent;
  }

  return Row(
    children: [
      SizedBox(
        width: 240,
        child: sessionsAsync.when(
          data: (sessions) => _SessionListPanel(
            sessions: sessions,
            currentSessionId: currentSessionId,
          ),
          loading: () => const _SessionListPanelLoading(),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: mainContent),
    ],
  );
},
```

- [ ] **Step 5: Extend `_SessionListPanel` with optional drawer-close behavior**

Update `_SessionListPanel` like this:

```dart
class _SessionListPanel extends ConsumerWidget {
  const _SessionListPanel({
    required this.sessions,
    required this.currentSessionId,
    this.closeAfterSelect = false,
  });

  final List<ChatSession> sessions;
  final String? currentSessionId;
  final bool closeAfterSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('最近会话', style: Theme.of(context).textTheme.titleMedium),
        ),
        if (sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('暂无会话'),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final selected = session.id == currentSessionId;
                return ListTile(
                  selected: selected,
                  title: Text(session.title),
                  subtitle: Text(DateFormat('MM-dd HH:mm').format(session.updatedAt)),
                  onTap: () async {
                    await ref.read(chatSessionControllerProvider).selectSession(session.id);
                    if (closeAfterSelect && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 6: Run the AI chat widget test file to verify green**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected:

- All AI chat page widget tests pass, including the new phone-drawer and wide-sidebar layout tests.

- [ ] **Step 7: Commit**

```bash
git add lib/features/ai_chat/presentation/ai_chat_page.dart test/features/ai_chat/presentation/ai_chat_page_test.dart
git commit -m "feat: add responsive ai chat sessions layout"
```

---

## Task 5: Add failing tests for stage-aware download status mapping

**Files:**
- Create: `test/features/ai_models/presentation/model_download_status_view_model_test.dart`
- Create: `lib/features/ai_models/presentation/model_download_status_view_model.dart`

- [ ] **Step 1: Write the failing status-mapping test file**

Create `test/features/ai_models/presentation/model_download_status_view_model_test.dart` with this content:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_download_status_view_model.dart';

void main() {
  test('maps zero-byte downloading task to connecting stage', () {
    final task = ModelDownloadTask(
      id: 'task-1',
      modelId: 'bge-small-zh',
      sourceId: 'source-1',
      status: ModelDownloadStatus.downloading,
      totalBytes: 10485760,
      downloadedBytes: 0,
      averageSpeed: null,
      errorMessage: null,
      resumable: true,
      createdAt: DateTime(2026, 5, 2, 10, 0, 0),
      updatedAt: DateTime(2026, 5, 2, 10, 0, 1),
    );

    final viewModel = ModelDownloadStatusViewModel.fromTask(task);

    expect(viewModel.stageLabel, '连接中');
  });

  test('maps failed task to failed stage and preserves error message', () {
    final task = ModelDownloadTask(
      id: 'task-1',
      modelId: 'bge-small-zh',
      sourceId: 'source-1',
      status: ModelDownloadStatus.failed,
      totalBytes: 10485760,
      downloadedBytes: 0,
      averageSpeed: null,
      errorMessage: 'DioException [connection timeout]',
      resumable: true,
      createdAt: DateTime(2026, 5, 2, 10, 0, 0),
      updatedAt: DateTime(2026, 5, 2, 10, 0, 1),
    );

    final viewModel = ModelDownloadStatusViewModel.fromTask(task);

    expect(viewModel.stageLabel, '失败');
    expect(viewModel.errorMessage, 'DioException [connection timeout]');
  });
}
```

- [ ] **Step 2: Run the targeted test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_download_status_view_model_test.dart
```

Expected:

- The test fails because `model_download_status_view_model.dart` does not exist yet.

- [ ] **Step 3: Implement the minimal status mapping helper**

Create `lib/features/ai_models/presentation/model_download_status_view_model.dart` with this content:

```dart
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';

class ModelDownloadStatusViewModel {
  const ModelDownloadStatusViewModel({
    required this.stageLabel,
    required this.errorMessage,
  });

  final String stageLabel;
  final String? errorMessage;

  factory ModelDownloadStatusViewModel.fromTask(ModelDownloadTask task) {
    final stageLabel = switch (task.status) {
      ModelDownloadStatus.idle => '未开始',
      ModelDownloadStatus.queued => '已发起',
      ModelDownloadStatus.downloading when task.downloadedBytes == 0 => '连接中',
      ModelDownloadStatus.downloading => '下载中',
      ModelDownloadStatus.paused => '已暂停',
      ModelDownloadStatus.completed => '已完成',
      ModelDownloadStatus.failed => '失败',
    };

    return ModelDownloadStatusViewModel(
      stageLabel: stageLabel,
      errorMessage: task.errorMessage,
    );
  }
}
```

- [ ] **Step 4: Run the new test file to verify green**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_download_status_view_model_test.dart
```

Expected:

- Both tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_models/presentation/model_download_status_view_model.dart test/features/ai_models/presentation/model_download_status_view_model_test.dart
git commit -m "feat: add model download status view model"
```

---

## Task 6: Integrate the stage-aware status helper into the model page and provider tests

**Files:**
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Import and use the new status view model in `model_management_page.dart`**

Add this import to `lib/features/ai_models/presentation/model_management_page.dart`:

```dart
import 'package:note_secret_search/features/ai_models/presentation/model_download_status_view_model.dart';
```

Then replace the temporary `_displayStageLabel(task!)` usage with:

```dart
final statusViewModel = ModelDownloadStatusViewModel.fromTask(task!);
```

and:

```dart
Expanded(child: Text(statusViewModel.stageLabel)),
```

- [ ] **Step 2: Surface the same stage label in failure and timestamp-heavy states**

Inside `_DownloadStatusCard.build`, add a compact summary line like this after the stage row:

```dart
Text('任务说明：${_statusDescription(task!.status)}'),
const SizedBox(height: 8),
```

but keep the new stage label as the primary state copy so users see `连接中` before raw task details.

- [ ] **Step 3: Add a provider test proving `startDownload` immediately persists a visible task state**

Add this test to `test/features/ai_models/application/model_download_providers_test.dart`:

```dart
test('startDownload persists downloading task immediately before first-byte progress', () async {
  final repository = _MemoryDownloadRepository();
  final registryRepository = _MemoryRegistryRepository();
  final downloadService = _FakeDownloadService(
    result: const ModelDownloadResult(
      localPath: '/models/bge-small-zh.onnx',
      totalBytes: 10485760,
      verifiedChecksum: 'sha256:abc',
    ),
  );

  final container = ProviderContainer(
    overrides: [
      modelDownloadRepositoryProvider.overrideWithValue(repository),
      modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
      modelDownloadServiceProvider.overrideWithValue(downloadService),
      modelCatalogEntriesProvider.overrideWith((ref) async => const [_embeddingEntry]),
    ],
  );

  addTearDown(container.dispose);

  unawaited(
    container.read(modelDownloadControllerProvider).startDownload(
          entry: _embeddingEntry,
          source: _embeddingEntry.sources.first,
        ),
  );

  await Future<void>.delayed(Duration.zero);
  final persistedTask = await repository.findLatestTaskByModelAndSource(
    _embeddingEntry.id,
    _embeddingEntry.sources.first.id,
  );

  expect(persistedTask, isNotNull);
  expect(persistedTask!.status, ModelDownloadStatus.downloading);
});
```

- [ ] **Step 4: Run the affected model/provider tests to verify green**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected:

- All tests in both files pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_models/presentation/model_management_page.dart test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/presentation/model_management_page_test.dart
git commit -m "feat: improve model download status feedback"
```

---

## Task 7: Run focused verification and Huawei device smoke

**Files:**
- Validate: `lib/features/ai_models/presentation/model_management_page.dart`
- Validate: `lib/features/ai_chat/presentation/ai_chat_page.dart`
- Validate: `lib/features/ai_models/presentation/model_download_status_view_model.dart`
- Validate: `test/features/ai_models/presentation/model_management_page_test.dart`
- Validate: `test/features/ai_chat/presentation/ai_chat_page_test.dart`
- Validate: `test/features/ai_models/application/model_download_providers_test.dart`
- Validate: `test/features/ai_models/presentation/model_download_status_view_model_test.dart`

- [ ] **Step 1: Run focused Flutter tests**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
flutter test test/features/ai_models/application/model_download_providers_test.dart
flutter test test/features/ai_models/presentation/model_download_status_view_model_test.dart
```

Expected:

- All targeted tests pass.

- [ ] **Step 2: Run analyzer**

Run:

```powershell
flutter analyze
```

Expected:

- `No issues found!`

- [ ] **Step 3: Build and install the debug APK on the Huawei device**

Run:

```powershell
flutter build apk --debug
adb -s H8B4C19731000256 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected:

- Debug APK builds successfully.
- adb install succeeds on the Huawei device.

- [ ] **Step 4: Unlock the app with the user-provided PIN and validate the model page layout fix**

Run / perform:

```powershell
adb -s H8B4C19731000256 exec-out uiautomator dump /dev/tty
```

Manual expectations on device:

1. Enter PIN `1234` if prompted.
2. Open `/models`.
3. Confirm `BGE Small 中文 Embedding` no longer shows vertically stacked current-source text.
4. Confirm no striped overflow indicator appears around the source/status section.

- [ ] **Step 5: Validate immediate download feedback on device**

Manual expectations on device:

1. Tap the model download action.
2. Confirm the status area changes promptly from idle into an active stage such as `已发起` or `连接中`.
3. Confirm the visible status changes before meaningful MB progress appears.

- [ ] **Step 6: Validate responsive AI chat layout on device**

Manual expectations on device:

1. Open `/ai/chat` on the Huawei phone.
2. Confirm the main chat area is no longer compressed by a permanent 240 px recent-session rail.
3. Confirm a hamburger button appears in the top-left app bar.
4. Tap it and confirm `最近会话` opens in a drawer.
5. Select an existing session and confirm the drawer closes and the current session changes.

- [ ] **Step 7: Commit**

```bash
git add lib/features/ai_models/presentation/model_management_page.dart lib/features/ai_chat/presentation/ai_chat_page.dart lib/features/ai_models/presentation/model_download_status_view_model.dart test/features/ai_models/presentation/model_management_page_test.dart test/features/ai_chat/presentation/ai_chat_page_test.dart test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/presentation/model_download_status_view_model_test.dart
git commit -m "feat: fix chat and model layout status feedback"
```

---

## Self-Review

### Spec coverage

The plan covers all approved spec requirements:

1. Model page source/status/action restructuring — Tasks 1, 2, and 6.
2. Phone drawer + wide sidebar chat layout — Tasks 3 and 4.
3. Faster perceived download-status feedback — Tasks 5 and 6.
4. Huawei phone verification using PIN `1234` — Task 7.

### Placeholder scan

No `TODO`, `TBD`, or “add appropriate handling” placeholders remain. Every implementation step includes concrete file paths, code blocks, and commands.

### Type consistency

The plan uses the same production names across tasks:

1. `ModelDownloadStatusViewModel`
2. `_ModelSourceSection`
3. `_SessionListPanel.closeAfterSelect`
4. `pumpChatRouteAtSize(...)`

No later task relies on undefined alternative names.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-02-chat-and-model-layout-status.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

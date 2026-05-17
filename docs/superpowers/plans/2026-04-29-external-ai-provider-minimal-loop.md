# External AI Provider Minimal Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the existing external AI provider skeleton so the app can save one OpenAI-compatible provider, load and edit it from settings, use it as a chat fallback when local LLM is unavailable, and require a first-send privacy confirmation before sending private context externally.

**Architecture:** This is a completion pass, not a greenfield feature. Keep the current local-first chat path unchanged, strengthen the `ai_providers` repository and settings flow, and add a UI gating layer for outbound private-context sends. Persist provider config in `provider_configs` via the existing `CryptoService`, use `SharedPreferences` only for per-provider privacy acknowledgement, and keep all behavior behind the existing Riverpod providers.

**Tech Stack:** Flutter, Dart, Riverpod, GoRouter, Dio, sqflite_sqlcipher, SharedPreferences, flutter_test.

---

## File Map

### Existing files to modify
- `lib/features/ai_providers/application/ai_provider_providers.dart`
  - Keep provider wiring, but add any missing read helpers and invalidation behavior.
- `lib/features/ai_providers/infrastructure/sqlite_external_provider_repository.dart`
  - Harden load/save behavior and ensure saved configs can be loaded back for editing.
- `lib/features/ai_providers/presentation/external_provider_settings_page.dart`
  - Load existing config into the form, preserve existing values, and keep save/test UX minimal.
- `lib/features/ai_chat/presentation/free_chat_tab.dart`
  - Add confirmation gating for outbound private-context sends in free chat.
- `lib/features/ai_chat/presentation/private_qa_tab.dart`
  - Add confirmation gating for outbound private-context sends in private QA.
- `lib/features/ai_chat/application/ai_chat_providers.dart`
  - Keep orchestration logic minimal; only add helper APIs if UI needs backend preview or provider lookup.

### Existing tests to modify/extend
- `test/features/ai_providers/application/ai_provider_providers_test.dart`
- `test/features/ai_providers/presentation/external_provider_settings_page_test.dart`
- `test/features/ai_chat/application/ai_chat_providers_test.dart`
- `test/features/ai_chat/presentation/ai_chat_page_test.dart`

### New files only if truly needed
- Avoid new abstractions unless current files become unreadable.
- If a small reusable chat confirmation helper becomes necessary, prefer one focused file under `lib/features/ai_chat/presentation/` and one matching widget test extension.

---

### Task 1: Make the provider settings page load persisted config

**Files:**
- Modify: `lib/features/ai_providers/application/ai_provider_providers.dart`
- Modify: `lib/features/ai_providers/presentation/external_provider_settings_page.dart`
- Modify: `test/features/ai_providers/application/ai_provider_providers_test.dart`
- Modify: `test/features/ai_providers/presentation/external_provider_settings_page_test.dart`

- [ ] **Step 1: Write the failing provider test for loading the enabled config**

```dart
test('enabledExternalProviderProvider returns the latest enabled config for editing', () async {
  final repository = _MemoryExternalProviderRepository(
    configs: const [
      ExternalProviderConfig(
        id: 'provider-disabled',
        providerType: ExternalProviderType.openAiCompatible,
        displayName: '旧配置',
        baseUrl: 'https://old.example.com/v1',
        apiKey: 'old-key',
        modelName: 'old-model',
        embeddingModelName: null,
        enabled: false,
        allowSensitiveFields: false,
      ),
      ExternalProviderConfig(
        id: 'provider-enabled',
        providerType: ExternalProviderType.openAiCompatible,
        displayName: '当前配置',
        baseUrl: 'https://example.com/v1',
        apiKey: 'secret-key',
        modelName: 'gpt-4.1-mini',
        embeddingModelName: 'text-embedding-3-small',
        enabled: true,
        allowSensitiveFields: true,
      ),
    ],
  );

  final container = ProviderContainer(
    overrides: [
      externalProviderRepositoryProvider.overrideWithValue(repository),
    ],
  );

  addTearDown(container.dispose);

  final config = await container.read(enabledExternalProviderProvider.future);

  expect(config?.id, 'provider-enabled');
  expect(config?.displayName, '当前配置');
  expect(config?.allowSensitiveFields, isTrue);
});
```

- [ ] **Step 2: Write the failing widget test for prefilled settings form**

```dart
testWidgets('external provider settings page preloads saved config into the form', (tester) async {
  final repository = _MemoryExternalProviderRepository(
    configs: const [
      ExternalProviderConfig(
        id: 'openai-compatible-default',
        providerType: ExternalProviderType.openAiCompatible,
        displayName: '我的 OpenAI 兼容服务',
        baseUrl: 'https://example.com/v1',
        apiKey: 'secret-key',
        modelName: 'gpt-4.1-mini',
        embeddingModelName: 'text-embedding-3-small',
        enabled: true,
        allowSensitiveFields: true,
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        externalProviderRepositoryProvider.overrideWithValue(repository),
        externalProviderClientProvider.overrideWithValue(_RecordingExternalProviderClient()),
      ],
      child: const MaterialApp(home: ExternalProviderSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.widgetWithText(TextFormField, '我的 OpenAI 兼容服务'), findsOneWidget);
  expect(find.widgetWithText(TextFormField, 'https://example.com/v1'), findsOneWidget);
  expect(find.widgetWithText(TextFormField, 'gpt-4.1-mini'), findsOneWidget);
  expect(find.widgetWithText(TextFormField, 'text-embedding-3-small'), findsOneWidget);
  expect(find.byType(SwitchListTile), findsOneWidget);
});
```

- [ ] **Step 3: Run the focused tests to verify RED**

Run:

```powershell
flutter test test/features/ai_providers/application/ai_provider_providers_test.dart test/features/ai_providers/presentation/external_provider_settings_page_test.dart
```

Expected: widget test fails because the settings page does not preload the saved config.

- [ ] **Step 4: Implement minimal load-on-open behavior**

```dart
@override
void initState() {
  super.initState();
  Future.microtask(_loadExistingConfig);
}

Future<void> _loadExistingConfig() async {
  final config = await ref.read(enabledExternalProviderProvider.future);
  if (!mounted || config == null) {
    return;
  }

  _displayNameController.text = config.displayName;
  _baseUrlController.text = config.baseUrl;
  _apiKeyController.text = config.apiKey;
  _modelNameController.text = config.modelName;
  _embeddingModelNameController.text = config.embeddingModelName ?? '';

  setState(() {
    _allowSensitiveFields = config.allowSensitiveFields;
  });
}
```

- [ ] **Step 5: Re-run the focused tests to verify GREEN**

Run:

```powershell
flutter test test/features/ai_providers/application/ai_provider_providers_test.dart test/features/ai_providers/presentation/external_provider_settings_page_test.dart
```

Expected: PASS.

---

### Task 2: Verify repository persistence preserves one enabled provider and decryptable config

**Files:**
- Modify: `lib/features/ai_providers/infrastructure/sqlite_external_provider_repository.dart`
- Modify: `test/features/ai_providers/application/ai_provider_providers_test.dart`

- [ ] **Step 1: Add the failing repository behavior test**

```dart
test('saving an enabled config disables older configs of the same provider type', () async {
  final repository = _MemoryExternalProviderRepository(
    configs: const [
      ExternalProviderConfig(
        id: 'provider-1',
        providerType: ExternalProviderType.openAiCompatible,
        displayName: '旧配置',
        baseUrl: 'https://old.example.com/v1',
        apiKey: 'old-key',
        modelName: 'old-model',
        embeddingModelName: null,
        enabled: true,
        allowSensitiveFields: false,
      ),
    ],
  );

  await repository.save(
    const ExternalProviderConfig(
      id: 'provider-2',
      providerType: ExternalProviderType.openAiCompatible,
      displayName: '新配置',
      baseUrl: 'https://example.com/v1',
      apiKey: 'secret-key',
      modelName: 'gpt-4.1-mini',
      embeddingModelName: null,
      enabled: true,
      allowSensitiveFields: false,
    ),
  );

  final all = await repository.loadAll();
  expect(all.where((item) => item.enabled), hasLength(1));
  expect(all.where((item) => item.enabled).single.id, 'provider-2');
});
```

- [ ] **Step 2: Run the provider tests to verify RED/GREEN as needed**

Run:

```powershell
flutter test test/features/ai_providers/application/ai_provider_providers_test.dart
```

Expected: if green already, do not change production code; keep current repository implementation and move on.

- [ ] **Step 3: Only if needed, adjust repository save logic minimally**

```dart
if (normalized.enabled) {
  await txn.update(
    DatabaseSchema.providerConfigs,
    <String, Object?>{
      'enabled': 0,
      'updated_at': now.millisecondsSinceEpoch,
    },
    where: 'provider_type = ?',
    whereArgs: <Object>[normalized.providerType.name],
  );
}
```

- [ ] **Step 4: Re-run provider tests**

Run:

```powershell
flutter test test/features/ai_providers/application/ai_provider_providers_test.dart
```

Expected: PASS.

---

### Task 3: Add first-send privacy confirmation for free chat external private-context sends

**Files:**
- Modify: `lib/features/ai_chat/presentation/free_chat_tab.dart`
- Modify: `test/features/ai_chat/presentation/ai_chat_page_test.dart`

- [ ] **Step 1: Write the failing widget test for free chat confirmation**

```dart
testWidgets('free chat asks for confirmation before sending private context to external provider', (tester) async {
  final repository = _FakeChatSessionRepository();
  final container = await buildContainer(
    llmReadiness: const LocalLlmReadiness(
      ready: false,
      reason: '尚未选择本地 LLM 模型。',
      activeModel: null,
      runtimeState: null,
    ),
    semanticReadiness: const SemanticSearchReadiness(
      ready: true,
      reason: 'ready',
      activeEmbeddingModel: _embeddingModel,
    ),
    externalStatus: const ExternalProviderStatus(
      available: true,
      reason: '外部模型已可用：OpenAI 兼容服务',
      config: ExternalProviderConfig(
        id: 'provider-1',
        providerType: ExternalProviderType.openAiCompatible,
        displayName: 'OpenAI 兼容服务',
        baseUrl: 'https://example.com/v1',
        apiKey: 'secret-key',
        modelName: 'gpt-4.1-mini',
        embeddingModelName: 'text-embedding-3-small',
        enabled: true,
        allowSensitiveFields: true,
      ),
    ),
    chatRepository: repository,
  );

  final router = container.read(appRouterProvider);
  router.go('/ai/chat');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('自由聊天'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('允许参考私密内容'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, '帮我回忆 GitHub 登录信息');
  await tester.tap(find.text('发送'));
  await tester.pumpAndSettle();

  expect(find.text('你即将把私密内容发送到外部模型'), findsOneWidget);
  expect(repository.savedMessages, isEmpty);
});
```

- [ ] **Step 2: Run the widget test to verify RED**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected: FAIL because send happens immediately and no confirmation dialog appears.

- [ ] **Step 3: Implement minimal free-chat confirmation gating**

```dart
Future<void> _handleSend(BuildContext context, WidgetRef ref, String value) async {
  final externalStatus = await ref.read(externalProviderStatusProvider.future);
  final controller = ref.read(externalPrivacyConfirmationControllerProvider);
  final state = ref.read(freeChatControllerProvider);

  final shouldConfirm = externalStatus.available &&
      externalStatus.config != null &&
      state.allowPrivateContext &&
      !await controller.hasAcknowledged(externalStatus.config!.id);

  if (shouldConfirm) {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('外发私密内容确认'),
            content: const Text('你即将把私密内容发送到外部模型，请确认你理解相关风险。'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('继续发送')),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await controller.markAcknowledged(externalStatus.config!.id);
  }

  await ref.read(freeChatControllerProvider.notifier).send(value);
}
```

- [ ] **Step 4: Re-run the widget test to verify GREEN**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected: PASS for the new confirmation test.

---

### Task 4: Add first-send privacy confirmation for private QA external sends

**Files:**
- Modify: `lib/features/ai_chat/presentation/private_qa_tab.dart`
- Modify: `test/features/ai_chat/presentation/ai_chat_page_test.dart`

- [ ] **Step 1: Write the failing widget test for private QA confirmation**

```dart
testWidgets('private QA asks for confirmation before sending externally retrieved private context', (tester) async {
  final repository = _FakeChatSessionRepository();
  final container = await buildContainer(
    llmReadiness: const LocalLlmReadiness(
      ready: false,
      reason: '尚未选择本地 LLM 模型。',
      activeModel: null,
      runtimeState: null,
    ),
    semanticReadiness: const SemanticSearchReadiness(
      ready: true,
      reason: 'ready',
      activeEmbeddingModel: _embeddingModel,
    ),
    externalStatus: const ExternalProviderStatus(
      available: true,
      reason: '外部模型已可用：OpenAI 兼容服务',
      config: ExternalProviderConfig(
        id: 'provider-1',
        providerType: ExternalProviderType.openAiCompatible,
        displayName: 'OpenAI 兼容服务',
        baseUrl: 'https://example.com/v1',
        apiKey: 'secret-key',
        modelName: 'gpt-4.1-mini',
        embeddingModelName: 'text-embedding-3-small',
        enabled: true,
        allowSensitiveFields: true,
      ),
    ),
    chatRepository: repository,
  );

  final router = container.read(appRouterProvider);
  router.go('/ai/chat');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, '帮我总结邮箱账号');
  await tester.tap(find.text('发送'));
  await tester.pumpAndSettle();

  expect(find.text('你即将把私密内容发送到外部模型'), findsOneWidget);
  expect(repository.savedMessages, isEmpty);
});
```

- [ ] **Step 2: Run the widget test to verify RED**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected: FAIL because private QA sends immediately.

- [ ] **Step 3: Implement minimal private-QA confirmation gating**

```dart
onSend: (value) async {
  final externalStatus = await ref.read(externalProviderStatusProvider.future);
  final confirmation = ref.read(externalPrivacyConfirmationControllerProvider);

  final shouldConfirm = externalStatus.available &&
      externalStatus.config != null &&
      !await confirmation.hasAcknowledged(externalStatus.config!.id);

  if (shouldConfirm) {
    final confirmed = await _showExternalPrivacyDialog(context);
    if (!confirmed) {
      return;
    }
    await confirmation.markAcknowledged(externalStatus.config!.id);
  }

  await controller.send(value);
}
```

- [ ] **Step 4: Re-run the widget test to verify GREEN**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected: PASS for private QA confirmation.

---

### Task 5: Ensure acknowledgement suppresses repeated prompts

**Files:**
- Modify: `test/features/ai_chat/presentation/ai_chat_page_test.dart`
- Modify: `lib/features/ai_chat/presentation/free_chat_tab.dart`
- Modify: `lib/features/ai_chat/presentation/private_qa_tab.dart`

- [ ] **Step 1: Add the failing widget test for one-time acknowledgement**

```dart
testWidgets('confirmed external privacy acknowledgement suppresses subsequent prompts', (tester) async {
  SharedPreferences.setMockInitialValues({
    'ai.external_privacy_ack.provider-1': true,
  });

  // Build same container as prior external-provider tests.
  // Enable private context, send message.

  expect(find.text('你即将把私密内容发送到外部模型'), findsNothing);
});
```

- [ ] **Step 2: Run the widget test to verify RED/GREEN**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected: if it already passes because acknowledgement is respected, keep production code unchanged.

---

### Task 6: End-to-end code health verification

**Files:**
- Modify only files touched above.

- [ ] **Step 1: Run provider and chat focused tests**

Run:

```powershell
flutter test test/features/ai_providers/application/ai_provider_providers_test.dart test/features/ai_providers/presentation/external_provider_settings_page_test.dart test/features/ai_chat/application/ai_chat_providers_test.dart test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run diagnostics/analyze**

Run:

```powershell
flutter analyze
```

Expected: exit code 0.

- [ ] **Step 3: Run Android emulator smoke**

Manual smoke checklist:

```text
1. Open /settings.
2. Tap 外部模型.
3. Confirm saved config preloads if one exists.
4. Tap 测试连接 and verify success/error feedback.
5. Open /ai/chat with local LLM unavailable.
6. Confirm runtime banner mentions external provider availability.
7. In 自由聊天, enable 允许参考私密内容 and send a message.
8. Confirm first send shows privacy dialog.
9. Confirm subsequent send does not re-prompt after acknowledgement.
10. In 私密内容问答, verify the same first-send confirmation behavior.
```

- [ ] **Step 4: Record only feature-caused fixes**

```text
If analyze/tests reveal pre-existing unrelated failures, document them separately and do not expand scope.
```

---

## Self-Review

- Covered requirements:
  - Settings entry and route: already present, verified and retained.
  - Provider config persistence: retained and explicitly verified.
  - API key storage through `CryptoService`: already in repository path and preserved.
  - Chat external fallback: already present and protected by tests.
  - First-send privacy confirmation: added as the missing UI-layer requirement.
  - Verification: focused tests, analyze, emulator smoke included.
- No placeholder tasks remain; every task maps to real existing files.
- Plan avoids broad security refactors and sync work.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-29-external-ai-provider-minimal-loop.md`.

User instruction overrides the normal choice point: proceed with inline execution immediately in this session, starting with Task 1 failing tests.

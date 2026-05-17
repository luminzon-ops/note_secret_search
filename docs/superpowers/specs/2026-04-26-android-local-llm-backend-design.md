# Android 本地 LLM Backend 设计

## 1. 背景与目标

当前项目已经完成《本地LLM首批开发设计方案.md》中的大部分 A/B/C 主链：

- Flutter 侧 LLM bridge / engine / providers 已建立；
- 模型管理页已接入 LLM readiness 展示与下载后校验；
- `/ai/chat` 页面、双 Tab、私密问答 / 自由聊天、可选私密上下文、多会话持久化与恢复基本完成；
- SQLCipher-backed chat session/message persistence 已完成。

当前剩余的关键缺口在 A 子系统：

- `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt` 仍为 stub；
- `generateText()` 仍返回 `[LOCAL_LLM_STUB]` 前缀文本；
- `ensureModelReady()` 尚未通过真实 backend 的最小推理探针来建立 `ready` 状态。

因此，本设计的目标是：

> 在不推翻现有 Flutter/UI/Provider/Persistence 主链的前提下，将 Android 本地 LLM runtime 从 stub 升级为真实本地推理 backend 适配层，使“本地 LLM 是否真正可运行”可以被诚实验证，并让 `/models` 与 `/ai/chat` 使用真实本地生成链路。

---

## 2. 设计原则

### 2.1 不偏离既有主线

本设计严格服务于《本地LLM首批开发设计方案.md》的 A 子系统收口，不转向新的产品能力，不扩展超出第一版范围的聊天特性。

### 2.2 保持 Flutter 主链稳定

以下 Flutter 对外接口尽量保持不变：

- `LlmRuntimeBridge`
- `LocalLlmEngine`
- `llmRuntimeStatesProvider`
- `activeLocalLlmModelProvider`
- `localLlmReadinessProvider`
- 现有 `/models` 与 `/ai/chat` 页面

这样可以避免 B/C 的已有实现被大范围扰动。

### 2.3 Android 侧做可替换 backend 适配

`LocalLlmRuntime` 不直接绑定单一实现细节，而是依赖 backend 抽象。这样第一版可以先落一个真实 backend，后续如果需要更换底层推理实现，不会影响 Flutter 主链。

### 2.4 readiness 必须由真实探针建立

`ready` 状态不再由 stub 或纯静态检查得出，必须满足：

1. 模型文件存在；
2. backend 可加载；
3. 可以完成一次真实最小推理；
4. 返回非空文本；
5. session 可继续复用或安全释放。

---

## 3. 架构分层

本设计采用 4 层结构。

### 3.1 Flutter 调用边界层

保留现有文件作为稳定调用边界：

- `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`
- `lib/features/ai_chat/infrastructure/local_llm_engine.dart`
- `lib/features/ai_chat/application/llm_runtime_providers.dart`

职责：

- 发起 MethodChannel 调用；
- 将 Android 返回值映射成 `LlmRuntimeState` / `LlmInferenceResponse`；
- 不感知 Android 具体 backend 实现。

### 3.2 Android Channel 层

继续使用：

- `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt`

职责：

- 处理 Flutter 调用：
  - `inspectModel`
  - `ensureModelReady`
  - `generateText`
  - `releaseModel`
- 进行参数校验；
- 统一错误映射：
  - `INVALID_ARGUMENT`
  - `RUNTIME_NOT_READY`
  - `LLM_RUNTIME_ERROR`

此层不直接实现推理逻辑。

### 3.3 Android Runtime Facade 层

保留并改造：

- `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`

职责：

- 检查模型文件是否存在；
- 使用 backend factory 选择可用 backend；
- 协调 sessionManager；
- 执行 readiness probe；
- 执行真实生成；
- 统一输出 runtime result map。

该类是 Android 本地 LLM runtime 的 orchestration facade，不再假造生成结果。

### 3.4 Android Backend 实现层

新增 backend 抽象层：

- `LocalLlmBackend.kt`
- `LocalLlmBackendSession.kt`
- `LlmBackendFactory.kt`

必要时再新增某个具体 backend 实现，如：

- `GgufLlamaCppBackend.kt`（名称示意，以实际选型为准）

职责：

- 对模型格式和 backend 支持性进行判断；
- 加载 session；
- 执行最小生成；
- 执行正式生成；
- 释放 session；
- 屏蔽 JNI / native / 第三方推理库细节。

---

## 4. Backend 接口设计

### 4.1 `LocalLlmBackend`

建议提供以下语义能力：

- `supports(modelPath, metadata?)`
- `inspect(modelPath)`
- `load(modelId, modelPath)`
- `generate(session, prompt, options)`
- `release(session)`

该接口代表某一种 Android 本地 LLM 推理实现能力。

### 4.2 `LocalLlmBackendSession`

代表已经加载好的模型 session。应至少包含：

- `modelId`
- `modelPath`
- backend-specific session handle / native handle / interpreter 对象

此对象用于隔离 backend 会话对象与 `LocalLlmRuntime` 之间的边界。

### 4.3 `LlmBackendFactory`

职责：

- 根据模型路径、扩展名、可用 native 依赖、设备能力等条件，选择一个 backend；
- 如果无可用 backend，返回空或结构化失败结果；
- 不在 factory 中做正式推理，只负责 backend 选择。

---

## 5. `LocalLlmRuntime` 行为约定

### 5.1 `inspectModel(modelId, modelPath)`

职责：

1. 检查文件是否存在；
2. 判断是否有 backend 能识别或支持当前模型；
3. 返回：
   - `missing`
   - `installed_unverified`
   - `degraded`

约束：

- inspect 不默认承诺 `ready`；
- 即使文件存在，也只有在 backend 可识别、路径合法时才进入 `installed_unverified`；
- 如果模型格式明确不支持，可直接返回 `degraded`。

### 5.2 `ensureModelReady(modelId, modelPath)`

职责：

1. 检查文件存在；
2. 通过 factory 选择 backend；
3. 若 sessionManager 中已有该 model session，则复用；
4. 否则真实执行 `load()`；
5. 做一次最小生成 probe；
6. probe 成功且输出非空文本后返回 `ready`；
7. 任一步失败则释放 session，并返回 `degraded`。

约束：

- 只有 `ensureModelReady()` 能建立 `ready`；
- probe 成功后可保留 session 供正式生成复用；
- probe 失败必须 cleanup，避免留下脏 session。

### 5.3 `generateText(modelId, modelPath, prompt, usedPrivateContext)`

职责：

1. 若当前 session 不存在，则内部先执行 `ensureModelReady()`；
2. 使用 backend 执行真实生成；
3. 返回统一 map：
   - `text`
   - `finishReason`
   - `usedPrivateContext`
   - `status`
   - `reason`
   - `checkedAt`
   - `modelPath`

约束：

- 不再返回 `[LOCAL_LLM_STUB]` 文本；
- prompt 为空时直接抛 `INVALID_ARGUMENT`；
- 生成失败时，保守释放当前 session，避免损坏状态继续复用。

### 5.4 `releaseModel(modelId)`

职责：

- 释放当前活跃模型 session；
- 从 sessionManager 中清理引用。

约束：

- 必须幂等；
- 未加载 session 时不应抛致命错误。

---

## 6. Session 生命周期

### 6.1 单活跃模型策略

继续沿用设计文档既定策略：

- 第一版只缓存一个活跃 LLM 模型；
- 不做多模型并发缓存。

这与现有 `LlmModelSessionManager` 方向一致，也能降低内存和状态复杂度。

### 6.2 状态流转

推荐的生命周期：

```text
not loaded
  -> inspect
  -> installed_unverified
  -> ensureModelReady
  -> loaded session
  -> probe success
  -> ready
  -> generate*
  -> release
  -> unloaded
```

错误路径：

```text
installed_unverified / loading
  -> error
  -> degraded
  -> cleanup release
```

### 6.3 失败后的保守策略

若生成失败：

- 当前 session 视为可能不可靠；
- `LocalLlmRuntime` 应释放该 session；
- 下次调用重新 load；
- 错误通过 Flutter 主链回传。

---

## 7. 第一版 backend 选型策略

### 7.1 目标

本轮不接受“接口是真的，生成还是假的”的状态。第一版必须至少接入一个真实 Android 本地推理 backend。

### 7.2 推荐方向

推荐以 **GGUF / llama.cpp 风格 backend** 为主要目标：

- 与“本地模型文件下载到应用私有目录后直接加载”的产品心智最一致；
- 与现有 embedding runtime 的本地文件 / Android runtime / Flutter bridge 工程方式更一致；
- 更适合作为真实最小推理能力的第一版落地路径。

### 7.3 第一版必须做到

1. backend 能识别支持的模型文件；
2. backend 能创建 session；
3. `ensureModelReady()` 能执行真实最小生成 probe；
4. `generateText()` 能返回真实生成文本；
5. `releaseModel()` 能释放 session；
6. 错误状态能正确映射为 `missing / installed_unverified / degraded / ready`。

### 7.4 第一版明确不做

以下能力不属于本轮收口范围：

- streaming token output；
- 复杂 chat template 管理；
- 温度/top-k/top-p 参数面板；
- 多模型并发缓存；
- GPU/NPU 级别性能优化；
- 高级 prompt 模板系统；
- 多模型对比回答；
- 复杂引用高亮和深链跳转。

---

## 8. 错误状态与上层行为约定

### 8.1 runtime 状态语义

- `notInstalled`：没有模型路径或未安装；
- `missing`：registry 有路径但文件已缺失；
- `installedUnverified`：文件存在且 backend 可识别，但未完成真实 probe；
- `ready`：已通过真实 load + probe generation 验证；
- `degraded`：backend 不支持、native 库不可用、load/probe/generate 失败等。

### 8.2 与 B 层的关系

`/ai/chat` 与 orchestration 层不应知道底层 backend 细节。B 层只消费：

- readiness 是否可用；
- reason 是什么；
- generate 是否成功。

现有 `AiChatPage` / `PrivateQaTab` / `FreeChatTab` 的主要逻辑无需重写。

### 8.3 与 C 层的关系

C 层继续只处理：

- session persistence；
- message persistence；
- history restore；
- session switch。

真实 backend 接入不会改变 C 层边界，只会改变 assistant 文本的真实来源。

---

## 9. 测试策略

### 9.1 Android A 层必须补的验证点

1. **模型文件不存在**
   - `inspectModel()` -> `missing`
   - `ensureModelReady()` -> `missing`

2. **模型文件存在但 backend 不支持**
   - 返回 `installed_unverified` 或 `degraded`
   - reason 明确说明格式/依赖不支持

3. **load 成功 + probe 成功**
   - `ensureModelReady()` -> `ready`
   - 返回有效 `checkedAt` / `modelPath`

4. **generate 成功**
   - 返回真实文本；
   - 不再出现 `[LOCAL_LLM_STUB]`；
   - `finishReason` 有定义；
   - `usedPrivateContext` 透传正确。

5. **generate 失败**
   - 返回结构化错误；
   - session 被释放；
   - 下次可重新 load。

6. **release 幂等**
   - 已加载 session release 成功；
   - 未加载 session release 不应致命失败。

### 9.2 Flutter 层回归测试

保留并继续通过：

- `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`
- `test/features/ai_chat/application/llm_runtime_providers_test.dart`
- `test/features/ai_chat/application/ai_chat_providers_test.dart`
- `test/features/ai_chat/presentation/ai_chat_page_test.dart`
- model management 相关测试

建议增强：

- runtime state mapping 的 backend unsupported / probe failed / generate failed case；
- chat orchestration 在真实 runtime error 下的 assistant failed message persistence。

---

## 10. 本轮实现边界与完成标准

### 10.1 本轮必须完成

- backend 抽象与 factory；
- `LocalLlmRuntime` 改造成 orchestration facade；
- 至少一个真实 Android 本地推理 backend；
- 真正的 minimal generation probe；
- 真正的 `generateText()`；
- 状态与错误传播修正；
- 必要测试补充；
- `/models` 与 `/ai/chat` 的真实 backend 接线验证。

### 10.2 本轮完成标准

以下 6 条全部成立，才能称为 A 收口完成：

1. Android 侧不再使用 stub 文本生成；
2. 至少存在一个真实 backend 实现；
3. `ensureModelReady()` 通过真实最小生成建立 `ready`；
4. `/models` 页的 LLM readiness 与真实 backend 状态一致；
5. `/ai/chat` 发起生成时走真实 backend；
6. 失败状态能正确回传 Flutter，并在会话历史中保留。

---

## 11. 实现顺序建议

### Step 1

新增 backend 抽象：

- `LocalLlmBackend`
- `LocalLlmBackendSession`
- `LlmBackendFactory`

### Step 2

改造 `LocalLlmRuntime.kt`：

- 文件检查；
- backend 选择；
- session 协调；
- readiness probe；
- generate；
- release。

### Step 3

落第一个真实 backend：

- load；
- minimal generation；
- release。

### Step 4

修正状态映射与错误传播：

- model management；
- runtime providers；
- chat orchestration。

### Step 5

补测试并做 A + B/C 回归验证。

---

## 12. 最终结论

你明确要求“我要本地LLM”，因此当前阶段不能停留在 stub。该设计将下一阶段工作聚焦在：

> 以可替换 backend 架构为基础，把 Android `LocalLlmRuntime` 从假实现升级为真实本地推理链路，并确保 `/models` 与 `/ai/chat` 使用真实 backend 状态和真实生成结果。

这条路径既不偏离《本地LLM首批开发设计方案.md》的 A/B/C 主线，也不会推翻当前已完成的 B/C 主链。

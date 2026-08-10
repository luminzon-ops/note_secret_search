# Note Secret Search v0.2.0 Phase 6：Repair LLM, Chat, and External Privacy Boundaries

## 1. Checkpoint 与边界

- 基线固定为 `72771ee4c2b894f2632bf6fe4aa9cf3edc7e9f41`。
- 计划确认后先执行 Checkpoint A：创建 `codex/repair-phase-6` 和 `E:\Archive\Flutter\worktrees\note_secret_search-repair-phase-6`，保存本计划至 `docs/superpowers/plans/2026-07-22-note-secret-search-v0-2-phase-6-llm-chat-external-privacy.md`。
- 计划单独提交为 `docs: add phase 6 llm chat privacy plan`，运行 `git diff --check`，汇报提交号后停止。再次得到明确确认才实施生产代码。
- Phase 3、4、5、主工作树及只读参考树保持原样；不触碰用户列出的受保护文件。
- 不实现 Phase 7 的目录签名、模型下载、artifact trust、设备推荐或多模态能力；不改变 Phase 5 embedding、ORT、schema v6 搜索契约。
- Huawei SPN-AL00 API 29 继续作为发布硬门禁，设备未出现时不检查、不替代。

## 2. 缺陷证据

- `android/third_party/llamacpp-kotlin-0.2.0-huawei-safe.aar` SHA-256 为 `93c02780...ec9ce`，官方 0.2.0 为 `d9aff44c...a0bf2`；本地包和 `llamacpp_patch_work` 没有源码锁、可重放 patch、构建命令或 llama.cpp revision。
- `android/app/build.gradle.kts:37-42,52,59` 又通过 `pickFirsts`、`silent_llama_bridge` 和本地 AAR叠加二次二进制替换；反编译 `LlamaAndroid.kt:181` 会记录包含完整 prompt 的 completion 参数。
- `LlmRuntimePlugin.kt:36-69,140-170` 将 load/generate 投入 executor，但 `:88-91` 在平台线程直接 release；`LlmModelSessionManager.kt:3-31` 完全未同步；`MainActivity.kt:60-68` 未 detach LLM plugin。
- `GgufLlamaCppBackend.kt:101-125` 从 prompt 前部执行 `.take(maxPromptChars)`，可能删除末尾当前问题；`AiChatRequest` 在 `chat_context_models.dart:29-43` 没有历史。
- `ai_chat_providers.dart:363-380` 只组装当前问题；`:427-450` 手动 Secret/Note 只映射标题，不发送实际获准内容。
- `external_provider_consent.dart:18-25` 未绑定配置 ID 或 credential；授权存于 SharedPreferences。配置页 `external_provider_settings_page.dart:119-134` 保存时固定 `enabled: true`，没有 disable/revoke 控件。
- 搜索设置的 `allowExternalProviderAccess` 默认关闭，但聊天发送层完全不读取它；现有确认依赖 Widget 预检和可直接访问的 raw provider client。
- `ai_chat_conversation_controller.dart:207-221,297-303` 每轮重新构造 session creation time，并按本地 readiness 写 `lastModelId`，即使实际使用外部 provider。
- `sqlite_chat_session_repository.dart:91-98` UPSERT 覆盖 `created_at`；`chat_messages` 没有实际 backend/model/fingerprint 字段。
- `ai_chat_conversation_controller.dart:343-373` 将 raw provider/runtime exception 写入聊天消息。现有 AAR/native 测试以 fake 为主，instrumentation 本身不采集 Logcat，也没有真实并发、重复 free 或 callback exactly-once 证明。

## 3. AAR 供应链

- 以 `ljcamargo/kotlinllamacpp@b576a1ff0a4dc013893c9aee69b1df70b3cc9794` 为 wrapper 基线，锁定该提交中的确切 llama.cpp gitlink或源码树哈希，不使用 branch、tag 或动态 Maven 解析。
- 新增 source lock、上游 archive SHA-256、编号 patch、patch SHA-256、JDK/Gradle/AGP/NDK/CMake/Ninja、ABI、minSdk、编译器和完整 CMake 参数记录。
- 固定 JDK 17、NDK `28.2.13676358`、CMake `3.22.1`、`arm64-v8a`、minSdk 24 和 `armv8-a` baseline；关闭 dotprod、FP16、i8mm、native CPU 探测、示例、测试和网络功能。
- patch 删除 Kotlin completion 参数日志，并将 native 日志接到只接受稳定事件码的 sink；不得记录 prompt、token、response、路径或原始异常。
- 构建脚本使用固定 `SOURCE_DATE_EPOCH`、文件排序、ZIP 时间戳及 `-ffile-prefix-map`，在两个干净临时目录构建并要求最终 AAR SHA-256 完全相同。
- 生成可提交的 provenance、SBOM、AAR entry hashes 和 ELF/ABI审计结果；质量门禁重新构建并核对这些记录。
- 新 artifact 为单一 baseline AAR；删除旧 huawei-safe AAR、`llamacpp_patch_work`、`silent_llama_bridge` 和 `pickFirsts`，`LlamaContextAdapter` 直接包装已审计的上游接口。

## 4. Native Lifecycle 接口

- 引入唯一 `LlmLifecycleCoordinator`，公开 `inspect`、`ensureReady`、`generate(requestId)`、`cancel(requestId)`、`release(modelId)` 和 `close`。
- 状态固定为 `Empty -> Loading -> Ready -> Generating -> Cancelling -> Ready/Releasing -> Empty -> Closed`；所有状态转换由单 actor 串行处理。
- JNI load/generate/free 在单一 blocking executor 上运行；只有 `stopCompletion` 可从专用 control lane 并发调用，free 必须等待 generation 真正终止。
- session identity 包含 model ID、canonical path、可用的 verified checksum、AAR build ID 和 load config。相同 identity 合并 load；任何 identity 变化先取消、free，再 load。
- 一次只允许一个 generation；并发第二次请求返回 `BUSY`。request ID 与 session epoch 绑定，过期 native callback 被丢弃且 MethodChannel result exactly-once。
- cancel、unknown cancel、重复 release 和重复 detach 均幂等；release 成功只在 native free 完成后返回。
- detach 立即移除 channel handler并启动 close future；不再向旧 messenger回调，close future只在 cancel、generation unwind 和 free 完成后结束。
- 稳定错误码为 `INVALID_ARGUMENT`、`MODEL_MISSING`、`MODEL_UNSUPPORTED`、`BUSY`、`CANCELLED`、`LOAD_FAILED`、`GENERATION_FAILED`、`RELEASE_FAILED`、`RUNTIME_CLOSED`。
- Dart `LlmRuntimeBridge` 增加 `requestId`、可选 checksum、`cancelGeneration` 和 typed exception；聊天 controller 在停止、新会话、锁定和销毁时传播 cancellation。

## 5. Provider 与 Prompt Privacy

- 以 `ExternalChatGateway` 作为唯一外发 seam；raw OpenAI/Ollama adapters 不再暴露给 chat。Gateway 在实际网络调用前重新加载 enabled config、验证授权和 fingerprint。
- 基础 fingerprint 绑定 config ID、provider type、规范化 endpoint、chat model、credential SHA-256 digest 和 privacy-policy version；raw credential不进入 key、日志或错误。
- standard/private 使用独立授权 scope。private scope另绑定 `allowSensitiveFields` 和 context projection policy version。
- 新配置默认 disabled；schema v7 将现有 provider全部设为 disabled并要求重新 opt-in，同时建立“最多一个 enabled provider”的唯一约束。
- 设置页提供显式“启用外部 AI”“停用外部 AI”“撤销发送确认”。停用、revoke、credential/type/endpoint/model变化会取消匹配的在途请求并丢弃迟到响应。
- display name和时间戳变化不失效；等价 endpoint规范化不失效；private policy变化只失效private scope；身份或 credential变化同时失效两个 scope。
- local readiness、generation、timeout或cancel失败只返回本地错误，任何路径都不重试或转发至 external。
- 新增 `ChatPromptComposer` 和瞬时 `ChatContextProjector`。手动选择在发送时按 ID重新读取、解密和投影，不把明文正文保存在 controller state或context ID审计字段中。
- 本地 private prompt服从搜索字段策略；password仅在本地且 `includePasswordField=true` 时可投影。外部 prompt永久移除 vault password字段，即使 provider允许其他敏感字段。
- 固定 local prompt预算为现有 1200 字符，external预算为 4000 字符，历史最多6个完整轮次。先完整预留当前问题和结构文本；超长问题返回 `PROMPT_TOO_LARGE`，绝不截断问题。
- 剩余预算按“manual实际内容、最近完整history、auto summary”分配；history只保留完整 user/assistant轮次。外部只携带同 fingerprint且敏感级别不高于当前授权的既有外部轮次。
- native仅校验 composer输出未超预算，不再执行前缀 `.take()`。自由输入中的密码样文本视为用户主动消息；强制排除针对 vault password字段。

## 6. Session 与 Schema v7

- 新增 `ChatBackendUsage`：`actualBackend`、`actualModel`、可选 `providerFingerprint`。本地记录实际 runtime/AAR backend和registry model ID；外部记录provider type和配置 model。
- `AiChatResponse`、`LlmInferenceResponse`、external gateway result携带 usage；controller只从实际完成结果保存 provenance。
- schema v7为 `chat_messages` 增加可空 `actual_backend`、`actual_model`、`provider_fingerprint`。历史记录保持 NULL/unknown，不从 `last_model_id` 推测回填。
- `saveSession` UPSERT不再更新 `created_at`；首次创建时间不可变。`updated_at` 和 `last_model_id` 根据本次实际成功结果更新，失败请求不得伪造 backend/model。
- history忽略 loading、failed、system和不完整轮次；恢复旧 session时正确映射 nullable provenance。
- `startNewSession`、lock reset和新 origin继续重置 backend为 local、private toggle、manual selections、messages、errors和共享 session selection；恢复已有 session只恢复其持久化 private flag，manual selections仍为空。
- raw Dio/JNI异常映射为稳定用户消息后再持久化；内部日志只记录稳定 code、阶段和耗时。

## 7. RED→GREEN 提交切片

1. AAR provenance RED验证旧包不可复现且含敏感日志特征；GREEN完成锁定构建、双构建和替换。提交：`build(android): replace opaque llama aar with reproducible build`
2. Lifecycle RED覆盖同 identity、重复load、model switch、load failure和线程所有权；GREEN实现coordinator。提交：`fix(android): serialize local llm lifecycle`
3. Cancellation RED覆盖generate/cancel/release/detach及callback race；GREEN接入request ID、epoch和真实free acknowledgement。提交：`fix(android): make llm cancellation deterministic`
4. Bridge RED覆盖wire payload、typed errors和cancel；GREEN更新Dart/MethodChannel接口。提交：`fix(ai): propagate llm request identity and cancellation`
5. Schema RED覆盖v4/v5/v6升级、provider opt-out、provenance NULL和created_at；GREEN实现v7迁移与repository契约。提交：`feat(storage): add phase 6 chat provenance schema`
6. Provider RED覆盖opt-in、fingerprint、revoke、invalidation和late response；GREEN实现唯一gateway及设置控件。提交：`fix(ai): require explicit external provider authorization`
7. Privacy RED使用password/body/credential sentinels覆盖字段矩阵；GREEN实现瞬时projector和实际manual内容。提交：`fix(ai): project approved chat context fields`
8. Prompt RED覆盖预算边界、完整问题、完整轮次和provider-safe history；GREEN实现composer并移除native截断。提交：`fix(ai): preserve questions in bounded chat prompts`
9. Session RED覆盖reset、restore、actual backend/model和安全错误；GREEN完成controller/persistence接线。提交：`fix(ai): preserve chat session provenance`
10. 真实门禁 RED覆盖JNI并发、cancel、repeated release和Logcat；GREEN只修复真实测试揭示的问题。提交：`test(android): cover llm privacy and concurrency gates`

## 8. 测试与门禁

- JVM：coordinator状态机、线程ID、bounded admission、model switch、失败恢复、重复释放、detach、epoch、exactly-once及直接AAR adapter。
- Dart：provider失效矩阵、prompt/privacy矩阵、manual实际正文、password排除、history预算、无fallback、session restore、schema v7及raw error清理。
- Instrumentation：真实GGUF load/generate/cancel/release、并发MethodChannel调用、engine recreate和新的AAR日志行为。
- Logcat脚本清空并采集目标进程日志，拒绝prompt、context、model path、API key、credential digest、token、response及sentinel。
- 每个切片运行focused tests、受影响broader tests、`git diff --check`、敏感静态扫描和改动文件边界检查。
- 最终运行 `flutter analyze`、全量Dart tests、Android JVM tests、instrumentation Kotlin编译、debug APK、AAR双构建/provenance gate及完整质量脚本。
- Phase 5 embedding、真实ONNX、schema v6、search/index门禁保持通过；旧opaque AAR哈希断言由Phase 6 provenance gate替代，ORT及embedding artifacts不得变化。
- Phase 7隔离检查确认model catalog/download/trust/device profiler、multimodal和受保护model management文件未变。
- Huawei SPN-AL00 API 29出现后执行真实AAR生成、repeated load、model switch、cancel、release、engine recreate和敏感Logcat；此前门禁保持待执行。

# Note Secret Search v0.2.0 Phase 5：Repair the Android Embedding Runtime

## 1. 基线、工作树与执行边界

### 1.1 基线快照

- Phase 5 worktree：`E:\Archive\Flutter\worktrees\note_secret_search-repair-phase-5`
- 分支：`codex/repair-phase-5`
- 起点：`237c48db3aac61f482457f25f4a73f596a3fe587`
- Phase 3：`E:\Archive\Flutter\worktrees\note_secret_search-repair-phase-3`，
  `codex/repair-phase-3 @ 04340cb71d3f6255b32f92d27474a2ea2ad0db97`
- Phase 4：`E:\Archive\Flutter\worktrees\note_secret_search-repair-phase-4`，
  `codex/repair-phase-4 @ 237c48db3aac61f482457f25f4a73f596a3fe587`
- 主工作树：`E:\Archive\Flutter\note_secret_search`，
  `master @ 61a030bfa7da7dc42e2a7971a852be8950b40ecf`
- 参考 worktree：
  `C:\Users\Lenovo\.config\superpowers\worktrees\note_secret_search\real-onnx-embedding-runtime`，
  `feature/real-onnx-embedding-runtime @ 7eddd244a3f50155a686df9d47d42307214824ad`

创建前后使用 `git status --porcelain=v2 --branch -uall`、`git rev-parse
HEAD`、`git worktree list --porcelain` 逐项复核。主树现有
`lib/features/ai_models/presentation/model_management_page.dart` 修改，以及
`.agents/`、`.codex/`、`AGENTS.md` 和主路线图未跟踪内容必须保持原样。
Phase 3、Phase 4 必须保持干净；参考 worktree 的既有
`GeneratedPluginRegistrant.java` 修改必须保持原样。新 worktree 不得包含主树
用户文件。

### 1.2 Phase 5 负责的行为

Phase 5 只负责：

- 从 `OnnxValue`/`OnnxTensor` 读取真实 tensor 值；
- 根据真实 input/output `TensorInfo` 创建输入、校验 shape/dtype、pooling 和
  normalization；
- 解析 catalog tokenizer JSON 的 BERT normalizer、中文字符处理、
  pre-tokenization、special token、WordPiece 和 Unicode 行为；
- 将模型加载、checksum、tokenizer 解析和 inference 移到受控 Android worker；
- 实现带完整身份的 session cache、重复加载、模型切换、释放和取消；
- 接通 Dart bridge、EmbeddingEngine、模型替换/删除生命周期；
- 补齐 JVM、Dart、instrumentation、真实 ONNX、中文 golden 和长期索引测试。

### 1.3 明确不做

- 不重建或替换 llama.cpp/AAR，不修改 `LocalLlmRuntime`、GGUF backend 或
  GGUF session lifecycle。
- 不修改外部 provider、聊天 prompt、手动上下文或外部隐私确认。
- 不修改 Phase 4 schema v6、search scope、index fingerprint、chunk、
  fusion、排序或 AI auto-context 契约；只有为真实 embedding runtime 接入而
  修改调用边界，并用回归测试证明行为不变。
- 不用固定零向量、mock-only inference、跳过真实 inference、放宽断言或把
  ONNX/tokenizer/inference 放回 UI/platform thread。
- 不引入无界线程、无限队列、全局 session 单例或无法证明释放/取消语义的
  ownership。
- 不修改 Phase 6 文件。

## 2. 当前缺陷及代码证据

### 2.1 Tensor 输出、输入和后处理

- `android/app/src/main/kotlin/com/example/note_secret_search/OnnxEmbeddingRuntime.kt:114-119`
  从首个 output 推断 vector dimension，而不是先选择 catalog 指定的
  `runtime.outputName` 并验证其 tensor contract。
- `OnnxEmbeddingRuntime.kt:129-141` 无条件使用 `LongBuffer` 和
  `[1, sequenceLength]`，没有读取 input `TensorInfo` 的 INT32/INT64、
  rank、batch 或固定 sequence dimension。
- `OnnxEmbeddingRuntime.kt:154-158` 的 `outputs` 元素类型是
  `Map.Entry<String, OnnxValue>`；当前 `.value` 仍是 `OnnxValue` 包装器，
  代码却直接交给 `extractTokenVectors`/`extractFloatValues`。ORT 1.18 的
  正确路径是在 `OrtSession.Result.use` 内调用 `OnnxValue.getValue()`，
  并在 result 关闭前复制数据。
- `OnnxEmbeddingRuntime.kt:159-175` 没有用 output `TensorInfo` 约束数组
  形状，且在 output 不是预期数组时静默走空结果。
- `EmbeddingVectorPostProcessor.kt:15-20` 对未知 pooling 静默退回 CLS；
  `:22-32` 对未知 normalization 静默返回原值；`:39-58` 没有检查
  ragged row、非有限值、mask/sequence mismatch 或全零/零范数结果。
- `OnnxEmbeddingRuntime.kt:30-46` 的 inspect 临时 session 在异常路径
  可能未关闭；`:61-78` 的失败路径只释放 model-ID 槽位，不能处理
  identity 变化。

### 2.2 Catalog tokenizer 与现有实现

- `assets/model_catalog/built_in_catalog.json:3-23` 当前 embedding 是
  `bge_small_zh_v1_5`，max sequence length 256，三路输入，
  `last_hidden_state`、mean pooling、L2 normalization。
- `assets/model_catalog/tokenizers/bge_small_zh_v1_5_tokenizer.json` 是
  tokenizer JSON v1.0，词表 21128 项，含：
  `BertNormalizer(clean_text=true, handle_chinese_chars=true,
  strip_accents=null, lowercase=false)`、`BertPreTokenizer`、
  `TemplateProcessing`、`[PAD]/[UNK]/[CLS]/[SEP]/[MASK]`、WordPiece
  `##` continuation 和 `max_input_chars_per_word=100`。
- `WordpieceEmbeddingTokenizer.kt:19-21` 只有 `String.lowercase()` 和
  UTF-16 正则空白拆分；`:49-85` 用 UTF-16 `substring`，没有 BERT
  clean-text、中文逐字符、Unicode 标点、accent、supplementary-plane
  scalar、metadata special token 或最大词长语义。
- `WordpieceEmbeddingTokenizer.kt:14-17` 将 special token ID 回退到硬编码
  0/100/101/102，无法证明与 tokenizer metadata 一致。
- 当前真实 tokenizer golden（参考 tokenizers 0.22.2）包括：
  `中文搜索 -> [101,704,3152,3017,5164,102]`；
  `Hello, 世界！ -> [101,100,117,686,4518,8013,102]`；
  `密码：P@ssw0rd -> [101,2166,4772,8038,100,137,10239,8220,8129,8642,102]`；
  `U+20000中文 -> [101,100,704,3152,102]`。

### 2.3 Platform thread、Dart bridge 与索引调用链

- `EmbeddingRuntimePlugin.kt:24-63` 直接在 MethodChannel 回调中执行
  `inspectModel`、`ensureModelReady` 和 `embedText`，包含文件 I/O、
  tokenizer 解析、session load 和 ORT run；没有 worker、队列、request ID、
  cancellation 或 detach。
- `EmbeddingRuntimePlugin.kt:71-78` 仅读取当前四项 tokenizer/runtime 字段；
  `embedding_runtime_bridge.dart:11-105` 没有 checksum、request ID 或
  `cancelRequest`。
- `onnx_embedding_engine.dart:46-73` 只把 bridge 返回值映射为 vector，
  未校验 dimension、finite 或 cancellation。
- `search_index_service.dart:206-208` 串行等待每个
  `EmbeddingEngine.embed`；现有 write fence 在写入边界检查，不能中止
  tokenizer、session load 或正在运行的 ORT。

### 2.4 Cache、模型替换和生命周期

- `EmbeddingModelSessionManager.kt:5-33` 只按 model ID 保留一个未同步
  session，没有 path、verified checksum、tokenizer spec、runtime spec 或
  runtime implementation version。
- `OnnxEmbeddingRuntime.kt:182-189` 每次 embed 都重新读取并解析 tokenizer；
  tokenizer cache 与 session 没有共同 identity。
- `MainActivity.kt:41-58` attach embedding plugin，`cleanUpFlutterEngine`
  `:60-65` 只 detach security plugin；embedding channel/worker/session 未
  释放。
- `model_lifecycle_controller.dart:14-24` 先删除 artifact 再清 registry，
  没有先 await embedding release。
- `model_download_providers.dart:157` 在模型下载替换时先删已有文件；
  `model_selection_providers.dart:22-34` 切换 active model 只 invalidate
  write fence 和 preference，没有释放旧 session。

### 2.5 当前测试盲区

- Android JVM 目前只有简化 tokenizer 两个用例、
  `OnnxEmbeddingModelSpec` 两个 parser 用例和后处理三个用例；
  没有 `OnnxEmbeddingRuntime`、真实 `OnnxValue`、worker、session lifecycle、
  cancellation 或线程断言。
- `test/features/search/infrastructure/onnx_embedding_engine_test.dart`
  的 bridge 全是 fake，未验证 MethodChannel wire payload、checksum、取消或
  native 数值。
- Phase 4 index integration 使用确定性 fake `EmbeddingEngine`，必须保留并
 继续通过；它不能替代真实 ONNX 测试。
- 现有敏感 Logcat instrumentation 覆盖 LLM，不覆盖 embedding。

## 3. 领域术语与目标接口

### 3.1 Native 领域对象

- `SessionIdentity`：`modelId`、canonical `modelPath`、worker 重新核验的
  `verifiedSha256`、tokenizer spec canonical serialization、tokenizer asset
  content hash、runtime spec canonical serialization、runtime implementation
  version、ORT execution settings。
- `TokenizerDefinition`：解析后的 normalizer、pre-tokenizer、added/special
  tokens、post-processor template、WordPiece 参数、pad/unk/cls/sep IDs。
- `ModelIoContract`：每个 catalog input 的 name、INT32/INT64 dtype、rank、
  batch/sequence dimensions；指定 output 的 FLOAT dtype、rank、shape kind 和
  vector dimension。
- `EmbeddingWorkItem`：request ID、operation、model identity inputs、text、
  cancellation handle、一次性 completion callback。
- `CancellationHandle`：queued 状态可移除，running 状态可触发 ORT terminate，
  cancel 只生效一次，完成后 callback 不再重复触发。
- `SessionSlot`：单 worker 所有的 `Empty`、`Loading`、`Ready`、`Running`、
  `Closing`、`Closed` 状态和当前 identity。
- `VerifiedEmbeddingResult`：已复制的有限 `Float` vector、token count、
  vector dimension；不持有 `OnnxValue`、tensor、buffer 或 text 引用。

### 3.2 Dart 兼容接口

- 保留 `inspectModel`、`ensureModelReady`、`embedText`、`releaseModel` 方法名
  和现有成功 payload 字段。
- 在 bridge 方法中增加可选 `verifiedChecksum`、`requestId`；增加
  `cancelRequest(requestId)`。旧调用如果没有 checksum，native 仍可执行实际
  SHA-256 并建立 identity；若提供 checksum，必须比对，不匹配返回
  `CHECKSUM_MISMATCH`。
- `EmbeddingRequest` 增加可选 cancellation token，默认表示不可取消，保持
  Phase 4 fake engine 和所有现有构造调用源兼容。
- `EmbeddingEngine` 的 `getState`/`embed` 方法签名保持不变；取消通过
  request 内的 token 传播，不引入第二个 engine seam。
- `EmbeddingRuntimeBridge` 增加 typed `EmbeddingRuntimeException` 映射，
  但保留 MethodChannel error code 到稳定 domain code 的兼容转换。

## 4. Tensor 输入、输出、pooling 和 normalization 不变量

### 4.1 Model inspection

1. canonicalize model path，检查 regular file 和可读性。
2. worker 以 1 MiB buffer 计算 SHA-256；没有传入 checksum 时把计算值作为
   `verifiedSha256`，传入时要求格式为 `sha256:<64 hex>` 且完全匹配。
3. 创建临时 `SessionOptions` 和 session；所有路径均使用 `use/finally`。
4. 只允许 catalog 声明的 input names；缺少 required input、存在未声明的
   required graph input、outputName 不存在或 tokenizer asset 缺失，返回
   `MODEL_SCHEMA_UNSUPPORTED` 或 `TOKENIZER_SCHEMA_UNSUPPORTED`。
5. 每个 input 必须为 rank 2；batch 维固定值只能是 1，sequence 维固定值必须
   大于 0 且不超过 tokenizer max length；动态维以 `-1`/ORT 动态标记接受。
6. input dtype 只支持 `INT64` 和 `INT32`，按 `TensorInfo` 选择
   `LongBuffer` 或 `IntBuffer`；不能因为 metadata 写成三路就向 graph 填入
   不存在的 token type IDs。
7. 指定 output 必须是 tensor FLOAT；支持 `[1,S,D]` token output 和 `[1,D]`
   sentence output。固定维必须为正，动态维在 run 后解析；D 必须大于零。

### 4.2 Encoding and run

- tokenizer 先生成 logical IDs、mask 和 type IDs，不默认补到 256。
- 动态 sequence graph 使用 logical length；固定 sequence graph 使用 graph
  sequence length，必须保留 CLS/SEP 并用 PAD 补齐。若 logical length 超过
  graph/tokenizer上限，按 BERT 规则截断并确保最后一个有效 token 是 SEP。
- 每个输入 tensor 都在 `use` 中创建和关闭；`RunOptions` 每次 run 新建、
  关闭，并携带 request ID 作为内部 tag，tag 不含文本。
- `OrtSession.Result.use` 内按 `outputName` 取得 `OnnxValue`，调用
  `getValue()`，依据 `TensorInfo.getShape()` 复制成受控的
  `Array<FloatArray>`/vector，然后立刻丢弃 wrapper。
- 不回退到首 output，不接受字符串、DOUBLE、INT、ragged array、缺失值或
  shape/count 不一致。

### 4.3 Pooling and normalization

- `[1,S,D] + mean`：只累加 `attentionMask[index] == 1` 的行，mask 长度与
  input sequence 对齐，至少有一行有效，输出宽度全程一致。
- `[1,S,D] + cls`：取第一个有效 token；没有有效 token 返回
  `INVALID_OUTPUT`。
- `[1,D]` 只能使用 sentence-compatible pooling；catalog 当前 mean 只接受
  rank-3 token output，避免误将 sentence output 当 token output。
- pooling/normalization 只接受 catalog 支持的 `mean`、`cls`、`l2` 和明确的
  `none`；未知值拒绝，禁止静默 fallback。
- pooling 前后和 normalization 后检查所有值为 finite；L2 norm 必须大于
  0，结果维度不变，最终 norm 在 `1e-5` 内等于 1。

## 5. Tokenizer metadata、Unicode 与中文规则

### 5.1 Parser contract

- 只接受 tokenizer JSON `version == "1.0"`、`model.type == "WordPiece"`、
  `normalizer.type == "BertNormalizer"`、`pre_tokenizer.type ==
  "BertPreTokenizer"` 和 `post_processor.type == "TemplateProcessing"`。
- 读取 `added_tokens` 的 id/content/special/normalized/lstrip/rstrip，
  从 post-processor 的 single template解析 CLS/SEP及 type IDs；缺失 PAD、
  UNK、CLS 或 SEP 时返回 schema error，不使用硬编码 fallback。
- 读取 `unk_token`、`continuing_subword_prefix` 和
  `max_input_chars_per_word`；词表键按大小写敏感方式保存，不能使用会把
  `µ`/`μ` 等不同 Unicode key 合并的 parser。
- `catalog lowercase` 与 JSON normalizer lowercase 必须一致；显式
  `strip_accents` 优先，否则 `null` 按 BERT 规则跟随 lowercase。

### 5.2 Normalizer and pre-tokenizer

- 逐 Unicode code point 处理，不按 UTF-16 code unit 截断或匹配。
- `clean_text=true`：删除 NUL、replacement/control 字符，把 tab/newline/
  carriage return 等 whitespace 规范为 ASCII space。
- `handle_chinese_chars=true`：在 CJK 基本区和补充平面字符两侧插入空格；
  至少覆盖 BERT 常用 CJK ranges，补充平面按 scalar range 处理。
- 需要 strip accents 时先 NFD，再删除 Unicode combining marks；lowercase
  使用 `Locale.ROOT`，不对非 lowercase catalog 强制改变大小写。
- BERT pre-tokenizer 先 whitespace split，再隔离 ASCII/Unicode punctuation；
  `@`、`-`、全角标点和 ASCII 标点都必须成为独立 token 候选。
- added special token 使用最长匹配并保留其 metadata 语义；普通文本中的
  `[CLS]` 仍是普通输入 special token，post-processor 另外添加模板 CLS/SEP。

### 5.3 WordPiece and sequence template

- 每个 pre-token 按 code point 数量执行 `max_input_chars_per_word`；
  超限或无法完整拆分时只产生一个 `[UNK]`。
- 首 piece 使用原 token，continuation piece 使用 `prefix + suffix`；
  每轮从最长候选向后回退，全部匹配后才提交 pieces。
- single template 固定为 metadata 指定的 CLS + sequence A(type 0) + SEP(type
  0)；当前 bridge 是单文本 API，pair template只解析并拒绝未支持的 pair
  请求。
- truncate 必须为 SEP 预留位置；max sequence length 小于 2 直接拒绝。
  attention mask 对有效 token 为 1、PAD 为 0，type IDs 按 template 生成。

## 6. Worker、线程、队列、取消和错误传播

### 6.1 Worker admission

- 每个 `EmbeddingRuntimePlugin` 拥有一个 single-thread
  `ThreadPoolExecutor`，底层 `LinkedBlockingDeque` 容量 8，并使用
  `android.os.Process.THREAD_PRIORITY_BACKGROUND`。
- 用 outstanding semaphore 限制总 outstanding work item 为 8（一个运行中、
  最多七个排队）；第 9 个普通请求立即返回 `BUSY`，不复制或保存其文本。
- platform thread 只做参数类型/长度校验、request ID分配和 enqueue；任何
  model file I/O、checksum、JSON parse、ORT API 和 vector processing 都在
  worker执行。
- completion 统一通过 main looper 回调；用 atomic one-shot guard 保证
  `success/error` 只发送一次，即使 detach 与 worker error 同时发生。

### 6.2 Cancellation

- `cancelRequest` 只接受 opaque request ID；queued item 从 deque 移除并回收
  admission slot，running item 标记 cancelled。
- running item 保存当前 `RunOptions` 的 adapter；取消时调用
  `RunOptions.setTerminate(true)`，worker 在 tokenizer、hash、session load、
  input creation、run、output copy 前后都检查 token。
- 取消返回稳定 `CANCELLED`；取消一个已完成/未知 request 是幂等 no-op。
  取消后健康 session 仍可复用，并由下一次 inference 测试证明。
- release/detach 先拒绝新任务，取消相关 queued/running work，再在 worker
  上关闭 session；detach 不阻塞 platform thread。模型删除/替换的 Dart
  lifecycle 必须 await `releaseModel` 完成后才操作文件。

### 6.3 Error model and privacy

稳定错误码固定为：
`INVALID_ARGUMENT`、`MODEL_MISSING`、`CHECKSUM_MISMATCH`、
`TOKENIZER_SCHEMA_UNSUPPORTED`、`MODEL_SCHEMA_UNSUPPORTED`、
`INVALID_OUTPUT`、`BUSY`、`CANCELLED`、`RUNTIME_CLOSED`、
`ORT_FAILURE`。

日志只写阶段、稳定 error code、model ID、request operation 和耗时；不得写
model path、checksum、prompt/text、token 明文、完整 tensor 或完整 exception
message。返回给 UI 的既有 `modelPath` 字段可保留兼容，但不进入 logger。

## 7. Session cache、所有权和释放状态机

### 7.1 Identity and transitions

```
Empty
  -> Loading(identity)
  -> Ready(identity)
  -> Running(request)
  -> Ready(identity)
  -> Closing
  -> Empty
```

detach 后进入终态 `Closed`。worker 是唯一读写状态机的线程。

- identity 完全相同：复用 session、parsed tokenizer 和 `ModelIoContract`。
- model ID、canonical path、verified checksum、tokenizer payload/content hash、
  runtime payload 或 runtime implementation version 任一变化：先取消旧
  work，关闭旧 session，再建立新 identity。
- registry version/revision 单独变化不影响 ORT identity；Phase 4 的
  `searchIndexModelRevisionProvider` 继续负责索引 invalidation。
- `SessionOptions` 的 execution mode、inter-op=1、intra-op=
  `min(2, availableProcessors)`、ORT artifact version 都纳入 runtime
  identity。

### 7.2 Ownership

- `OrtEnvironment.getEnvironment()` 作为进程级 singleton，不由 plugin 关闭。
- 每个 temporary/session `SessionOptions`、input `OnnxTensor`、`RunOptions`、
  `OrtSession.Result` 和 output `OnnxValue` 都由创建方 `use/finally` 关闭。
- inspect 用临时 session；ensure/embed 使用 cache session；inspect 异常、
  validation error、checksum failure 和 cancellation 都必须清除 partial
  slot，不留下不可复用 session。
- `releaseModel` 对 model ID 不存在、已释放或重复调用均成功返回；close
  exception 记录稳定 code 后仍清空引用。
- Activity `cleanUpFlutterEngine` 调用 embedding plugin 的
  `detachFromEngine`；detach 后 channel handler 清空、worker 不再接受工作、
  session 最终关闭，不能影响 LLM plugin lifecycle。

### 7.3 Invalidation matrix

| 变化 | 预期行为 |
| --- | --- |
| identity 完全相同 | 重复 ensure 不新建 session；tokenizer 只解析一次 |
| model ID 变化 | 释放旧 model，再加载新 model |
| model path 变化 | canonical path 变化即关闭并重建 |
| checksum 变化/核验失败 | 旧 identity 关闭；新 identity 不进入 Ready |
| tokenizer asset/spec 变化 | tokenizer/session 一起失效 |
| runtime names/pooling/normalization 变化 | session contract 一起失效 |
| registry revision/version 变化 | ORT 可复用；索引 revision 仍失效 |
| model deletion/replacement | await release 完成后再删/覆盖文件 |
| queued cancellation | 从队列移除，释放 admission slot |
| running cancellation | terminate current run，session 可复用 |
| activity/engine detach | 拒绝新请求、取消、关闭全部 session，重复 detach 幂等 |

## 8. Dart bridge、EmbeddingEngine 和 Phase 4 接入

### 8.1 Bridge payload

- `_tokenizerPayload` 和 `_runtimePayload` 保留现有 snake/camel boundary
  适配，不改变 catalog JSON。
- `inspectModel`、`ensureModelReady`、`embedText` 增加可选
  `verifiedChecksum`、`requestId`；`embedText` request ID 必须存在。
- 新增 `cancelRequest({required String requestId})`；release 保持 model ID
  API并等待 native close acknowledgement。
- `OnnxEmbeddingEngine.getState` 从 `ModelRegistryEntry.checksum` 传入
  checksum；`embed` 传入同一 checksum，校验 returned vector dimension、
  finite 和 non-empty。
- native error code 映射为 typed Dart exception；旧 fake bridge 仍可返回
  现有 map，既有 engine state mapping 测试保持通过。

### 8.2 Cancellation seam

- `EmbeddingRequest` 添加 optional `EmbeddingCancellationToken`，默认 null。
  token 提供 `isCancelled`、`whenCancelled` 和一次性 cancel。
- `OnnxEmbeddingEngine` 为每次 bridge embed 生成 request ID，监听 token，
  在 token 取消时调用 `cancelRequest`，并确保监听器在成功、失败或取消后
  清理。
- `SearchIndexWriteFence` 保留现有 `revision`/`validate`，新增有界
  `SearchIndexWriteLease`：capture 时注册，`invalidate()` 增加 revision 并
  cancel 所有 active leases，operation 完成时 unregister。
- `SearchIndexService` 将 lease token 放入每个 `EmbeddingRequest`，在每个
  embed 前后调用 `validate`；真实 native cancellation 和既有 stale-write
  exception 两者均不得提交旧 index set。
- Phase 4 的确定性 fake engine 不需要执行 token 才能继续工作；新增测试证明
  fence validation 仍保护其写入边界，避免改变 Phase 4 排序/索引契约。

### 8.3 Model lifecycle

- `ModelLifecycleController` 注入 embedding runtime release callback；删除
  manifest 前先 await embedding `releaseModel`，再删除 primary/artifacts，
  最后 purge registry。
- download replacement 在删除旧文件或覆盖目标前释放同 model ID embedding
  runtime；checksum/path 变化后下一次 ensure 建立新 identity。
- active model selection 先 invalidate write fence，再 await 旧 embedding
  model release，持久化新选择并 invalidate providers。
- 只接入 embedding bridge；LLM model deletion/replacement 不进入 Phase 5
  runtime lifecycle。

## 9. 文件级改动范围

### 9.1 Android production

- 修改：
  `android/app/src/main/kotlin/com/example/note_secret_search/OnnxEmbeddingRuntime.kt`
  `WordpieceEmbeddingTokenizer.kt`、`OnnxEmbeddingModelSpec.kt`、
  `EmbeddingVectorPostProcessor.kt`、`EmbeddingModelSessionManager.kt`、
  `EmbeddingRuntimePlugin.kt`、`MainActivity.kt`。
- 新增小型职责类：
  `EmbeddingRuntimeWorker.kt`、`EmbeddingRuntimeError.kt`、
  `EmbeddingSessionIdentity.kt`、`OnnxRuntimeAdapter.kt`、
  `TokenizerJsonParser.kt`；每个文件保持单一 ownership/translation boundary。
- 不修改 `android/app/build.gradle.kts` 或 ORT 版本，除非真实 fixture
  编译证明现有 `onnxruntime-android:1.18.0` 缺少所需 API；若确需改动，必须
  单独 RED→GREEN 提交并证明不是升级 AAR/Phase 6。

### 9.2 Dart production

- 修改：
  `lib/features/search/domain/embedding_engine.dart`、
  `lib/features/search/infrastructure/embedding_runtime_bridge.dart`、
  `onnx_embedding_engine.dart`、`embedding_runtime_providers.dart`、
  `search_index_write_fence.dart`、`search_index_service.dart`、
  `model_lifecycle_controller.dart`、`model_download_providers.dart`、
  `model_selection_providers.dart` 及必要 provider wiring。
- 不修改 `lib/features/search` 的 schema、scope、chunk、fusion、ranking
  contract；如 diff 触及这些文件，必须回滚到 Phase 4 行为并重新确认边界。

### 9.3 Test/fixture files

- 扩展现有 Android JVM tests，新增 worker/session/runtime/parser tests。
- 新增 Dart bridge、engine、write-fence、lifecycle cancellation tests。
- 新增 instrumentation embedding runtime、真实 tensor、真实 catalog BGE、
  long-running indexing 和 sensitive logcat tests。
- 增加真实 tokenizer JSON golden fixture；增加一个小型真实 ONNX fixture，
  不使用固定向量替代 inference。BGE artifact 使用 E 盘质量缓存或测试设备
  已核验文件，不提交约 95MB 模型进仓库。

## 10. RED→GREEN TDD 提交切片

每个切片必须先提交/运行失败测试，随后只实现使当前 RED 变绿的最小代码，
运行 focused tests、相关 broader tests，再提交。不得跨切片预实现。

1. **Typed output and post-processing**
   - RED：fake `OnnxValue` 返回 `FloatArray`、`float[][]`、`float[][][]`、
     `FloatBuffer`；断言指定 output、dtype、shape、mask、finite、zero norm
     和 dimension 错误。
   - GREEN：引入 ORT adapter，调用 `getValue()`，在 `Result.use` 内复制，
     严格实现 output carrier、pooling 和 L2。
   - Commit：`fix(android): read typed ONNX embedding outputs`

2. **Tokenizer metadata and Chinese golden**
   - RED：用真实 BGE tokenizer JSON断言 metadata schema、中文逐字、标点、
     whitespace、大小写、accent、control、supplementary scalar、special
     token、unknown、continuation 和 100/101 code-point boundary。
   - GREEN：实现 parser、BertNormalizer、BertPreTokenizer、TemplateProcessing
     和 code-point WordPiece；保留 min fixture兼容。
   - Commit：`fix(android): match catalog BERT WordPiece tokenization`

3. **Input contract and dynamic shape**
   - RED：INT32/INT64 input、固定/动态 sequence、缺 input、额外 input、
     fixed batch 非 1、output rank/dtype mismatch。
   - GREEN：从 `TensorInfo` 构建 `ModelIoContract`，按 graph dtype/shape 创建
     tensor，并正确选择 logical/padded sequence。
   - Commit：`fix(android): validate embedding model IO contracts`

4. **Bounded worker and platform-thread non-blocking**
   - RED：记录 callback thread、阻塞 fake I/O 时 main heartbeat、8 outstanding
     成功及第 9 个 `BUSY`、one-shot callback、detach 拒绝新任务。
   - GREEN：实现单 worker、bounded deque/admission、main-looper callback、
     stable errors 和 privacy-safe logging。
   - Commit：`fix(android): offload embedding runtime work`

5. **Session identity and lifecycle**
   - RED：same identity repeated-load 只 create 一次；model ID/path/checksum/
     tokenizer/runtime 任一变化重建；load failure、double release、inspect
     exception 和 model switch 均无遗留 session。
   - GREEN：实现 `SessionIdentity`、`SessionSlot`、tokenizer/contract cache、
     close ownership 和状态转移。
   - Commit：`fix(android): key and release embedding sessions safely`

6. **Cancellation**
   - RED：queued cancel、running cancel、load/run race、cancel 后 session reuse、
     release priority、duplicate cancel/release、activity detach。
   - GREEN：接入 cancellation handle、ORT `RunOptions.setTerminate(true)`、
     worker cancellation和异步 teardown。
   - Commit：`fix(android): add embedding cancellation lifecycle`

7. **Dart identity/cancellation/lifecycle**
   - RED：wire payload checksum/request ID、cancelRequest、typed errors、write
     fence lease、index stale cancellation、model switch/delete release-before-
     file mutation。
   - GREEN：最小兼容更新 bridge/engine/providers/lifecycle；不改变 fake
     EmbeddingEngine 的 Phase 4结果。
   - Commit：`fix(search): propagate embedding runtime identity and cancellation`

8. **Real inference and device behavior**
   - RED：instrumentation tiny ONNX 数值、BGE golden vector、repeated-load、
     model-switch、50+ chunk indexing、no ANR、sensitive logcat。
   - GREEN：只补真实 fixture adapter/test hooks 和已经由 RED 证明的最小缺口。
   - Commit：`test(android): cover real embedding runtime behavior`

## 11. 测试矩阵

### 11.1 Android JVM focused tests

- `WordpieceEmbeddingTokenizerTest`：完整 BGE golden、code point、中文、
  punctuation、control/whitespace、accent/lowercase、unknown、continuation、
  truncation/padding/type IDs。
- `TokenizerJsonParserTest`：version、normalizer、pre-tokenizer、
  post-processor、added token、词表 Unicode key、unsupported schema。
- `OnnxEmbeddingModelSpecTest`：字段兼容、严格校验、canonical serialization。
- `EmbeddingVectorPostProcessorTest`：mean/CLS、mask mismatch、ragged、
  finite、zero norm、unknown operation。
- `OnnxEmbeddingRuntimeTest`：fake adapter 的真实 `OnnxValue` carrier、
  output selection、input dtype/shape、session close on every failure。
- `EmbeddingModelSessionManagerTest`：identity matrix、state machine、重复
  release、switch、close exception、no stale slot。
- `EmbeddingRuntimeWorkerTest`：single worker、bounded admission、BUSY、
  queue cancellation、running cancellation、callback exactly once、thread IDs。

### 11.2 Dart focused tests

- bridge payload tests：checksum/request ID/tokenizer/runtime fields和
  `cancelRequest` method name。
- engine tests：checksum forwarding、vector finite/dimension、typed
  `CANCELLED`/`BUSY`/`CHECKSUM_MISMATCH` mapping、token cleanup。
- write fence lease tests：invalidate cancels active lease、post-embed
  validation rejects stale write、release unregisters lease。
- lifecycle tests：model delete and replacement await release before artifact
  mutation；selection switch releases old ID before preference write。
- preserve all existing `onnx_embedding_engine_test.dart` fake bridge tests。

### 11.3 Instrumentation and real ONNX

- `EmbeddingRuntimeInstrumentationTest` 使用真实 ORT 1.18 和小型 ONNX
  fixture，验证 output numeric values、shape、mean+L2、Result close 后仍有
  copied vector。
- 用 pinned BGE artifact（catalog checksum
  `sha256:69a0b846f4f116b5e6aabf9546ea6754d02264f3211a13a1bd69b31b8040749a`）
  在 E 盘缓存核验后运行中文 corpus；不得用主树 MiniLM artifact 代替 BGE
  门禁。
- repeated-load、model-switch、checksum change、delete/recreate、
  cancellation、50+ chunks long-running indexing、engine/activity recreate。
- `EmbeddingSensitiveRuntimeLogInstrumentationTest` 断言 logcat 不含 model
  path、checksum、明文输入、token 或向量。

### 11.4 Broader regression

- 所有现有 Android JVM tests。
- 所有 Dart tests、Phase 4 search index integration/maintenance tests、
  schema v6、scope、fingerprint、chunk、fusion、ranking tests。
- debug APK、真实 Huawei SPN-AL00 API 29 instrumentation 和敏感 Logcat
  smoke。

## 12. 失败恢复、进程中断和资源验证

- checksum/tokenizer/schema/load 任一失败：关闭 temporary/new session，
  清除 identity/parsed tokenizer/contract，保持旧健康 session仅在新 identity
  尚未开始替换时可用；替换进行中失败则状态回到 Empty，不返回 Ready。
- cancel 在每个阶段都必须可观察为 `CANCELLED`，不写 index、不吞掉 stale
  fence；cancel 后下一次正常 embed 必须成功。
- process interruption 依赖 OS 回收 native handles；下一次 plugin attach
  从 Empty 重新核验文件和 checksum，不信任旧内存状态。
- repeated release、detach、unknown request cancellation、close exception
  都必须幂等；测试用 close counters 证明每个 session 最多 close 一次。
- 测试完成后检查 worker thread 数、queue outstanding、session count、
  tensor/result close counters 和 callback count，确保无泄漏、无双回调、
  无残留 work item。

## 13. 质量门禁、实施顺序与 Phase 6 隔离

### 13.1 每个垂直切片

1. 只运行当前 RED/GREEN focused tests。
2. 运行受影响的 Android JVM 或 Dart broader tests。
3. 运行 `git diff --check` 和敏感日志静态检查。
4. 检查 `git diff --name-only`，确认没有 Phase 4 schema/search行为或
   Phase 6 LLM/AAR 文件。
5. 通过后按第 10 节提交信息小步提交。

### 13.2 最终门禁

- `scripts/quality/Invoke-QualityChecks.ps1`，继续使用 E 盘质量缓存，不清理
  系统盘。
- 全量 Dart tests、Android JVM tests、debug APK。
- Huawei SPN-AL00 API 29：真实 BGE inference、中文 corpus、repeated-load、
  model-switch、cancellation、long-running indexing、detach/recreate。
- 敏感 Logcat smoke、`git diff --check`。
- 最终 worktree 必须干净；再次核对 Phase 3、Phase 4、主树和参考树状态。

### 13.3 Phase 4 regression gate

- Phase 4 已通过的 schema v6、search scope、index fingerprint、chunk、
  fusion、排序、AI auto-context和确定性 fake engine 测试必须原样通过。
- 不改变 index set replacement、stale write、model revision、vector dimension
  或 search evidence contract；任何行为变化必须有真实 runtime 接入的直接
  测试证据。

### 13.4 Phase 6 isolation gate

- `git diff --name-only` 不得包含 `LocalLlmRuntime`、GGUF backend、llama.cpp
  AAR、聊天 prompt、external provider 或隐私确认文件。
- AAR SHA-256 与 Phase 4 基线一致；不产生 `third_party`、Gradle dependency
  或 generated plugin registration 的无关变更。
- 最终报告列出 Phase 5 改动文件、测试证据和未完成的设备前置条件；若 BGE
  artifact 或 Huawei 设备不可用，保留明确的硬门禁失败记录，不以 MiniLM、
  mock 或固定向量替代。

# 真实 ONNX Embedding Runtime 集成设计

## 1. 背景

当前项目已经具备：

- 本地 SQLCipher 数据库与核心数据表；
- 密码条目与私密笔记 CRUD；
- 关键词搜索；
- embedding 索引表与语义检索业务链路；
- 模型目录、模型下载、模型选择页面骨架。

但当前语义检索底层仍依赖：

- `lib/features/search/infrastructure/placeholder_embedding_engine.dart`

该实现明确说明其仅用于“索引链路打通”，不代表真实语义质量。这意味着当前项目虽然在产品体验层已经建设了较完整的搜索解释、语义命中、详情页命中说明等能力，但尚未真正完成《产品开发实施方案》中 Milestone 4 所要求的：

1. ONNX Runtime Mobile 接入；
2. 本地 embedding 模型管理；
3. query embedding + 相似度计算；
4. 本地语义检索真正可用。

同时，当前 `ai_models` 模块已经具备：

- `model_registry`
- `download_tasks`
- `activeEmbeddingModelProvider`
- `ModelManagementPage`

但这些能力目前更多停留在“文件下载与记录管理”层，还没有升级到“模型真实可运行、可校验、可被搜索链路使用”的部署闭环。

因此，本设计的目标，是把项目从“占位 embedding 链路”升级为：

> **真实本地 ONNX embedding runtime + 模型管理联动 + 明确可观测运行态 + 可降级的语义搜索**

---

## 2. 目标

本次设计目标如下：

1. 用真实 ONNX embedding runtime 替换当前 placeholder embedding engine；
2. 保持 `EmbeddingEngine` 作为搜索业务层唯一依赖入口；
3. 让 active embedding model 真正参与索引与搜索；
4. 让模型管理页展示“真实部署状态”，而不是仅展示文件记录状态；
5. 当模型不可运行时，语义搜索明确降级，关键词搜索继续可用；
6. 为下一阶段的 benchmark、模型下载校验、本地 LLM runtime 接入保留清晰扩展位。

---

## 3. 非目标

本轮明确不包含以下内容：

1. 远程模型目录刷新；
2. 目录签名校验；
3. checksum 校验；
4. 断点续传；
5. 下载源测速与自动切源；
6. benchmark 完整体系；
7. 设备能力分级完整策略；
8. 本地 LLM 接入；
9. 外部 provider 接入（OpenAI / Ollama / Anthropic）；
10. iOS 支持；
11. 多模型并发 session 缓存；
12. 大规模索引性能优化；
13. 通用 tokenizer 框架抽象。

本轮重点是：

> **先把单一 active embedding 模型的真实本地推理闭环打通。**

---

## 4. 方案选择

候选方案共三类：

### 方案 A：单体直连型
- 在现有 `EmbeddingEngine` 背后直接通过 `MethodChannel` 调 Android ONNX Runtime；
- Flutter 直接把 `ModelRegistryEntry.localPath` 传到原生侧；
- 原生侧统一处理模型加载、推理、状态检查。

优点：
- 路径最短，最快验证真实向量链路。

缺点：
- Flutter 与原生 runtime 耦合较高；
- 后续接 benchmark、兼容性校验、模型切换时容易变乱；
- channel handler 责任容易膨胀。

### 方案 B：分层运行时型（最终采用）
- 搜索层继续只依赖 `EmbeddingEngine`；
- Flutter 基础设施层新增 `OnnxEmbeddingEngine` 与 runtime bridge；
- Android 侧新增独立 embedding runtime channel 与 runtime facade；
- 模型管理页、搜索 readiness、索引状态统一消费真实运行态。

优点：
- 最符合“发布闭环优先”；
- 能与当前 `EmbeddingEngine`、`model_registry`、`search` 架构自然衔接；
- 后续扩展 benchmark、下载后校验、本地 LLM runtime 更顺。

缺点：
- 改动范围较大；
- 需要同时修改 Flutter provider、搜索链路、模型管理页、Android 原生层。

### 方案 C：插件优先型
- 先把 embedding runtime 封成更独立的 Flutter plugin 模块，再由应用层消费；
- 搜索与模型管理都围绕插件协议集成。

优点：
- 边界最清晰，长期复用性最好。

缺点：
- 当前轮成本过高；
- 更像平台工程，不利于当前项目节奏。

### 最终决策

采用 **方案 B：分层运行时型**。

原因：

1. 当前任务目标不是 demo，而是“真实部署闭环优先”；
2. 项目已有 `EmbeddingEngine`、`activeEmbeddingModelProvider`、`model_registry`、`search index` 等架构基础，适合在现有结构上补 runtime 层；
3. 方案 B 既能完成本轮真实 embedding 接入，又能为下一任务“模型下载管理补强”留下自然延伸点。

---

## 5. 总体架构

### 5.1 核心原则

1. 搜索业务层不直接感知 ONNX Runtime；
2. `EmbeddingEngine` 仍是 embedding 调用的唯一业务入口；
3. 模型下载成功不等于模型可运行；
4. 运行失败必须可见，不能静默回退成 placeholder engine；
5. 关键词搜索始终可用，语义搜索按 readiness 明确降级；
6. 当前阶段只缓存一个 active embedding model 的原生 session。

### 5.2 Flutter 侧分层

#### 领域层
保留现有抽象：

- `EmbeddingEngine`
- `EmbeddingRequest`
- `EmbeddingVector`
- `EmbeddingEngineState`

其中 `EmbeddingEngineState` 将扩展语义，以支撑真实运行态。

#### 基础设施层
新增：

- `OnnxEmbeddingEngine`
- `EmbeddingRuntimeBridge`
- 可选的 runtime state mapper / DTO

职责：

- `OnnxEmbeddingEngine`：实现 `EmbeddingEngine`，负责领域对象与 bridge 协调；
- `EmbeddingRuntimeBridge`：负责 `MethodChannel` 编解码与原生调用；
- mapper / DTO：负责把原生运行态结果映射成 Flutter 领域状态。

#### Provider 层
需要调整：

- `embeddingEngineProvider`
- `activeEmbeddingModelProvider`
- `semanticSearchReadinessProvider`
- `searchIndexStatusProvider`
- `modelRegistryEntriesProvider`

这些 provider 不再只看“数据库记录 + 文件是否存在”，而要纳入“runtime 是否可加载 / 可推理”判断。

### 5.3 Android 侧分层

#### Channel / Plugin 层
新增独立 channel：

- `note_secret_search/embedding_runtime`

不复用 `note_secret_search/native_security`，避免安全桥与模型推理耦合。

#### Runtime Facade 层
新增 Kotlin 类，例如：

- `EmbeddingRuntimePlugin`
- `OnnxEmbeddingRuntime`
- `EmbeddingModelSessionManager`

职责：

- 检查模型路径；
- 管理 ONNX session；
- 加载 / 切换 / 释放 active embedding model；
- 执行推理；
- 输出结构化运行态和错误。

#### ONNX 执行层
职责：

- 初始化 ONNX Runtime 环境；
- 加载模型文件；
- 构造输入张量；
- 读取输出张量；
- 做 pooling / normalization；
- 释放资源。

---

## 6. 模型生命周期与状态模型

### 6.1 状态枚举

embedding 模型的运行态分为：

1. `notInstalled`
   - 无 registry 记录，或无有效本地路径。

2. `installedUnverified`
   - 有 registry 记录，有本地文件，但还未做 runtime 校验。

3. `ready`
   - runtime 成功加载并通过最小推理校验；
   - 可用于索引与语义搜索。

4. `degraded`
   - 有文件，但不可运行；
   - 例如模型损坏、格式不支持、输出维度异常、runtime 初始化失败。

5. `missing`
   - registry 里有记录，但本地文件已不存在。

### 6.2 生命周期流转

#### 下载完成
- 文件落盘；
- 创建 / 更新 `ModelRegistryEntry`；
- 状态初始视为 `installedUnverified`。

#### 校验阶段
在以下场景触发 runtime inspect / ensure ready：

1. 模型下载完成后；
2. 打开模型管理页时；
3. 切换 active embedding model 时；
4. 搜索 readiness 刷新时；
5. 索引状态刷新时。

校验内容包括：

1. 文件存在性；
2. 模型是否能被 ONNX Runtime 加载；
3. 输入输出结构是否符合 embedding 预期；
4. 是否能完成最小推理；
5. 输出向量维度是否合法。

#### 激活阶段
- 用户选择 embedding 模型时，只允许 `ready` 状态模型成为真正 active model；
- 若用户选中 `installedUnverified`，则先触发校验；
- 校验失败则拒绝激活。

#### 搜索与索引使用阶段
- `SearchIndexService` 与 `SemanticSearchService` 只使用 `ready` 状态的 active embedding model；
- 若没有 ready 模型，则语义检索关闭，并在 UI 中明确展示原因。

---

## 7. Flutter 接口设计

### 7.1 `EmbeddingEngine`

保留现有接口：

- `Future<EmbeddingEngineState> getState(ModelRegistryEntry model)`
- `Future<EmbeddingVector> embed(EmbeddingRequest request)`

搜索业务层继续只依赖该抽象。

### 7.2 `EmbeddingEngineState`

现有仅包含：

- `ready`
- `reason`

本次将扩展为具备以下语义（字段名可在实现时调整，但语义必须保留）：

- `ready`
- `reason`
- `status`（notInstalled / missing / installedUnverified / ready / degraded）
- `vectorDimension`
- `modelPath`
- `checkedAt`

目的：

- 让搜索页、索引状态、模型管理页共享一套真实运行态表达；
- 避免每处页面自己拼状态逻辑。

### 7.3 `EmbeddingRequest`

保持轻量，仅保留：

- `model`
- `text`

不在 Flutter 业务层提前暴露 tokenizer、truncate、pooling 配置。当前阶段这些属于 runtime 实现细节。

### 7.4 `EmbeddingRuntimeBridge`

新增 bridge 抽象，职责：

1. 调用原生 `MethodChannel`；
2. 处理参数与返回值编解码；
3. 把原生错误映射成 Flutter 侧异常 / 状态对象。

建议提供以下方法：

- `inspectModel(...)`
- `ensureModelReady(...)`
- `embedText(...)`
- `releaseModel(...)`

---

## 8. Android 通信协议设计

### 8.1 独立 channel

新增 channel：

- `note_secret_search/embedding_runtime`

职责与安全相关 channel 分离。

### 8.2 原生暴露的方法

#### `inspectModel`
用途：

- 检查文件存在；
- 检查 runtime 是否可加载；
- 检查模型输入输出结构；
- 可选执行一次最小探测推理。

输入：

- `modelId`
- `modelPath`

输出：

- `status`
- `reason`
- `vectorDimension`
- `checkedAt`
- `runtime`
- `supportsEmbedding`

#### `ensureModelReady`
用途：

- 真正加载模型并建立 session；
- 将模型推进到 ready 状态。

输入：

- `modelId`
- `modelPath`

输出：

- 同 `inspectModel`。

#### `embedText`
用途：

- 对输入文本执行真实 embedding 推理。

输入：

- `modelId`
- `modelPath`
- `text`

输出：

- `values`
- `tokenCount`
- `vectorDimension`

#### `releaseModel`
用途：

- 释放 active model 对应 session；
- 为模型切换和内存控制留出扩展位。

输入：

- `modelId`

输出：

- void

---

## 9. 错误模型设计

### 9.1 Android 侧错误分类

原生层至少区分以下错误：

- `MODEL_FILE_MISSING`
- `MODEL_LOAD_FAILED`
- `MODEL_SCHEMA_UNSUPPORTED`
- `TOKENIZATION_FAILED`
- `INFERENCE_FAILED`
- `EMPTY_OUTPUT`
- `INVALID_VECTOR_DIMENSION`
- `RUNTIME_NOT_AVAILABLE`

### 9.2 Flutter 侧错误映射

Flutter 侧错误映射分三层：

#### 用户可理解层
用于 UI 提示：

- 模型文件缺失；
- 模型已安装但当前不可运行；
- 模型与当前 embedding runtime 不兼容；
- 推理失败，请重新校验或更换模型。

#### 业务状态层
用于 provider / readiness 逻辑：

- missing
- degraded
- not ready
- ready

#### 调试日志层
保留原始错误码与 message，用于开发排查。

---

## 10. Session 缓存策略

### 10.1 当前策略

当前阶段只缓存 **一个 active embedding model session**。

原因：

1. 与现有“active embedding model”概念一致；
2. 内存更可控；
3. 行为更稳定，便于调试；
4. 不把 MVP 阶段复杂度推高到多模型并发管理。

### 10.2 行为规则

1. 首次 `ensureModelReady` 时加载 session；
2. 后续 `embedText` 复用该 session；
3. 模型切换时可释放旧 session；
4. runtime inspect 可以不强制持久保留 session，但 ready 阶段应允许缓存复用。

---

## 11. Provider 与页面联动设计

### 11.1 `modelRegistryEntriesProvider`

当前仅基于数据库记录与文件存在性构造 `ModelRegistryEntry` 列表。

本次改造后，需增加运行态解析逻辑，最终页面消费对象应具备：

- registry entry
- filePresent
- runtimeStatus
- runtimeReason

这可以通过新增“resolved model runtime entry”类或等价结构实现。

### 11.2 `activeEmbeddingModelProvider`

当前逻辑：

- 只要 selection 中选中某个 embedding 模型，且该 entry installed，即认为 active。

改造后逻辑：

- 只有当 entry runtime 状态为 `ready` 时，才返回 active embedding model；
- 若模型文件缺失、未校验、校验失败，则返回 null。

### 11.3 `semanticSearchReadinessProvider`

改造后需要明确区分：

1. scope 关闭；
2. 未选择模型；
3. 模型文件缺失；
4. 模型未校验；
5. 模型校验失败；
6. runtime ready。

这样搜索页与索引状态才能展示真实原因。

### 11.4 `searchIndexStatusProvider`

继续承担：

- pending item 检测；
- engine readiness 检测。

但 `engineReady` 与 `engineReason` 将来自真实 runtime，而不再是 placeholder 说明。

### 11.5 `ModelManagementPage`

模型管理页的“部署状态”不再只看：

- 是否有 registry 记录；
- 文件是否存在。

而是升级为：

- 已安装且 runtime 校验通过；
- 已安装但文件缺失；
- 已安装但 runtime 加载失败；
- 已安装但不支持当前 embedding runtime；
- 未安装。

用户切换 active embedding model 时：

1. 先 `ensureModelReady`；
2. 成功才写 active selection；
3. 失败则拒绝切换并提示原因。

---

## 12. 搜索与索引链路接入方式

### 12.1 索引链路

`SearchIndexService.indexPendingItems(...)` 保持现有职责：

- 分段；
- 调 `EmbeddingEngine.embed(...)`；
- 写入 `embedding_chunks`。

本次仅将 `_embeddingEngine` 的具体实现替换为真实 `OnnxEmbeddingEngine`。

### 12.2 查询链路

`SemanticSearchService.search(...)` 保持现有职责：

- 生成 query embedding；
- 与已索引向量做 cosine similarity；
- 应用字段权重、质量门槛与排序逻辑。

本次仅将 query embedding 来源替换为真实 runtime。

### 12.3 失败与降级规则

#### active model 文件缺失
- runtime 状态标记 `missing`；
- `activeEmbeddingModelProvider` 返回 null；
- 语义搜索关闭；
- 模型页提示重新下载 / 删除失效记录。

#### 模型可见但 runtime 加载失败
- 状态标记 `degraded`；
- 保留 registry 记录；
- 不允许成为 active semantic model。

#### 推理失败
- 状态标记 `degraded`；
- 阻断索引与语义搜索；
- 不回退到 placeholder engine。

#### 无可用模型
- 关键词搜索继续可用；
- 语义搜索关闭；
- UI 明确提示本地 embedding 模型未就绪。

---

## 13. 实现范围

### 13.1 本轮必须完成

#### Android 原生 embedding runtime
- 接入 ONNX Runtime Android；
- 独立 embedding runtime channel；
- 支持加载一个本地 ONNX embedding 模型；
- 支持最小真实推理；
- 支持 readiness / inspect / release。

#### Flutter 真实 `EmbeddingEngine`
- `OnnxEmbeddingEngine` 替换 placeholder；
- `getState()` 返回真实 runtime 状态；
- `embed()` 返回真实向量。

#### 搜索链路真实化
- `SearchIndexService` 使用真实向量；
- `SemanticSearchService` 使用真实 query embedding；
- 模型不可用时语义搜索明确关闭。

#### 模型管理联动
- 已安装 embedding 模型可做 runtime inspect；
- active model 切换前先校验；
- 模型管理页展示真实部署状态。

#### 错误与降级
- 缺文件、加载失败、推理失败都可见；
- 关键词搜索继续可用；
- 语义搜索按 readiness 降级。

### 13.2 预计改动区域

#### Flutter
- `lib/features/search/domain/embedding_engine.dart`
- `lib/features/search/application/search_providers.dart`
- `lib/features/search/application/search_index_service.dart`
- `lib/features/search/application/semantic_search_service.dart`
- `lib/features/search/presentation/search_status_summary.dart`
- `lib/features/search/presentation/search_page.dart`
- `lib/features/ai_models/application/model_selection_providers.dart`
- `lib/features/ai_models/application/model_download_providers.dart`
- `lib/features/ai_models/presentation/model_management_page.dart`

新增：

- `lib/features/search/infrastructure/onnx_embedding_engine.dart`
- `lib/features/search/infrastructure/embedding_runtime_bridge.dart`
- 可能的 runtime DTO / mapper 文件。

#### Android
- 新增 embedding runtime plugin / manager；
- 更新 Android Gradle 依赖，引入 ONNX Runtime；
- 注册 embedding runtime channel。

---

## 14. 测试策略

### 14.1 Flutter 单元测试
必须覆盖：

1. `OnnxEmbeddingEngine` 状态映射；
2. readiness provider；
3. active embedding model 切换时的校验逻辑；
4. runtime 不可用时的语义搜索降级逻辑。

### 14.2 Flutter Widget / Presentation 测试
必须覆盖：

1. 模型管理页展示真实部署状态；
2. 搜索状态页显示 runtime not ready / degraded；
3. 不可用模型不能被当作 active embedding model。

### 14.3 Android 最小验证
至少保证：

1. 原生层可加载模型；
2. 原生最小输入推理成功；
3. 输出向量维度稳定且非空；
4. 缺文件路径时能返回明确错误。

若本轮不做完整 Android 自动化测试，则必须提供可重复手工验证路径。

### 14.4 本轮验收标准

本轮任务完成的验收标准固定为：

1. 一个已安装的本地 embedding ONNX 模型可被 runtime 校验为 ready；
2. 用户可将其设为 active embedding model；
3. 编辑一条 secret / note 后，索引写入真实 embedding 向量；
4. 搜索 query 使用真实 embedding 参与语义检索；
5. 模型损坏 / 缺失时，语义搜索明确降级而不是伪装可用。

---

## 15. 分阶段落地顺序

### 第一步：原生 runtime 跑通
目标：

- ONNX Runtime Android 接上；
- 原生可以加载模型并返回向量。

### 第二步：Flutter engine 接通
目标：

- `OnnxEmbeddingEngine` 可调用原生；
- `EmbeddingEngine.getState()` 与 `embed()` 真实化。

### 第三步：provider 与 readiness 改造
目标：

- active model / readiness / runtime state 流转正确；
- 搜索页和模型页都能感知真实运行态。

### 第四步：搜索链路替换
目标：

- index 与 query 都走真实 embedding；
- placeholder engine 不再参与主流程。

### 第五步：模型管理页与错误处理收尾
目标：

- 模型部署状态可见；
- 模型切换行为正确；
- 降级与错误提示清晰。

---

## 16. 后续任务衔接建议

本轮完成后，最合理的下一任务是：

## 模型下载管理补强

建议优先补：

1. checksum 校验；
2. 下载完成后自动 runtime 校验；
3. 文件损坏识别；
4. 下载失败恢复；
5. 下载状态恢复。

原因：

- 本轮会让“模型能运行”；
- 下一轮应让“模型能稳定下载并被可信使用”；
- 这正好对应 `Milestone 6` 的核心缺口。

而不建议本轮后立刻转向：

- 本地 LLM；
- 外部 provider；
- 更多 explainability 文案打磨。

---

## 17. 最终结论

本设计将当前项目从：

- 占位 embedding engine
- 文件记录式模型管理
- 语义链路表面可用但真实推理未接入

升级为：

- 真实 ONNX embedding runtime
- 模型管理页可观测的真实部署状态
- active embedding model 真正参与索引与搜索
- 模型不可运行时明确降级而不是静默伪装可用

这将使项目首次真正满足《产品开发实施方案》中关于“本地 embedding 模型部署并应用于语义检索”的核心要求，并为后续：

- benchmark
- 模型下载完整运维能力
- 本地 LLM runtime

提供稳定的架构基础。

# Milestone 6-B 自动切源与轻量探测排序设计

## 1. 目标

本设计聚焦 **Milestone 6：模型下载管理** 的第二执行切片：**自动切源 + 轻量探测排序**。

Milestone 6-A 已经补齐了同一下载源上的断点续传与应用重启后的恢复语义，但当前模型下载仍然存在一个明显缺口：

1. 用户虽然可以手动切换下载源，但主下载链仍然只会尝试当前 source；
2. 一旦当前 source 超时、限流、5xx 或 checksum 不匹配，任务会直接失败；
3. 当前 UI 和部分 controller helper 仍带有“一个 model 只有一个 latest task”的假设，这与现有 `modelId + sourceId` 任务维度已经开始脱节。

因此，本轮目标不是把模型下载系统扩展成完整的下载平台，而是把当前主链推进到一个更接近可交付的状态：

1. 用户选中的下载源仍然是首选来源；
2. 当首选来源失败时，系统能够自动尝试其余来源，而不是立刻把整个模型下载判定为失败；
3. 备用来源的尝试顺序能够基于轻量探测结果做出更合理的排序，而不是永远死板按目录顺序重试；
4. 自动切源不会破坏 6-A 已完成的 resume 语义；
5. 页面上的任务状态、当前来源与按钮语义保持可解释，不把 source-aware 行为重新退化成 model-aware 假象。

---

## 2. 当前现状

当前仓库已经具备如下与 6-B 高度相关的能力：

1. `ModelDownloadTask` 已按 `modelId + sourceId` 维度建任务；
2. `ModelDownloadController.startDownload()` 已经负责 enqueue → inspect partial → download → checksum → registry → runtime 校验整条主链；
3. `ModelDownloadService` 已经支持单一 source 的 partial inspect、Range resume 与 restart fallback；
4. `ModelManagementPage` 已支持手动切换 source，并已存在 source-aware 的 pause/start 路径；
5. `built_in_catalog.json` 当前已存在同一模型的多个 source，具备自动切源的真实触发条件。

但当前仍有三个结构性断层：

### 2.1 当前 source 失败会直接终止整次下载

`ModelDownloadController.startDownload()` 当前只接收一个 `source` 并只下载一次。只要该 source 失败，就调用 `markFailed()` 结束任务。

### 2.2 resume 与 target file 是文件路径驱动，而不是 source 隔离驱动

当前 `ModelDownloadService.inspectDownloadTarget(modelId, sourceUrl)` 解析出的目标文件路径本质上仍是 **`modelId + URL extension`**。这意味着：

- 同一 source 的 resume 是安全的；
- 不同 source 很可能会指向同一目标文件；
- 因此跨 source 复用 partial bytes 在当前结构下并不安全。

### 2.3 页面与部分 helper 仍保留 model-level latest task 假设

当前仍存在如下 model-aware 读取：

1. `_CatalogSection._latestTaskFor(modelId)`
2. `ModelDownloadController.markFailed(modelId, ...)`
3. `ModelDownloadController.markCompleted(modelId)`
4. `ModelDownloadController.markDownloading(modelId)`

这在只有一个 source 活跃时问题不大，但一旦 source A 失败后自动切到 source B，就可能出现：

- 页面显示的是 source A 的失败态，但真正下载中的其实是 source B；
- model-level helper 更新错了任务行；
- pause / retry / 状态卡不再与当前 source 对齐。

---

## 3. 范围界定

### 3.1 本轮明确纳入

本轮只做以下 5 项：

1. **自动切源**
   - 用户选中的 source 仍然先尝试；
   - 若失败且属于可切源错误，则自动尝试剩余来源；
   - 直到某个来源成功，或所有来源都失败。

2. **轻量探测排序**
   - 在真正下载前，对备用来源做轻量探测；
   - 以 reachability / status / range support / 轻量延迟 等信息决定备用来源排序；
   - 探测结果只在本次下载过程中使用，不持久化。

3. **同 source resume，跨 source restart**
   - 若当前尝试的 source 与已有 partial 文件对应的是同一 source，则继续沿用 6-A resume 语义；
   - 若自动切换到另一个 source，则从 0 开始，不复用旧 partial bytes。

4. **source-aware task 更新与展示修正**
   - controller 中所有 source-specific 状态更新必须以 `modelId + sourceId` 为准；
   - 页面上的状态卡、当前来源和操作按钮必须能正确反映自动切源后的 source。

5. **失败语义分级**
   - 明确哪些错误会触发自动切源；
   - 明确哪些错误会直接终止整次下载。

### 3.2 本轮明确排除

以下内容不在 6-B 范围内：

1. probe/测速历史持久化；
2. benchmark / 设备能力评级增强；
3. source 健康度长期学习；
4. target file 命名结构重构为 source-specific；
5. 新数据库表或 `download_tasks` schema 扩展；
6. 下载签名校验；
7. 后台下载服务与系统通知。

---

## 4. 方案对比

### 方案 A：Controller 编排 + 轻量 Probe Helper（推荐）

做法：

- `ModelDownloadController.startDownload()` 扩展为多 source 尝试循环；
- 新增一个轻量 `ModelSourceProbeService`，只负责单 source 探测；
- `ModelDownloadService` 继续保持“单 source 下载原语”；
- UI 只补 source-aware task 选择与最小文案。

优点：

- 与现有 controller-heavy orchestration 完全一致；
- 最小 diff；
- TDD 成本最低；
- 不需要 schema 变更。

缺点：

- controller 会比 6-A 更复杂；
- probing 与 downloading 之间仍需一个显式的编排层。

### 方案 B：把多 source orchestration 下沉到 `ModelDownloadService`

做法：

- service 接收 source 列表；
- 在 infrastructure 层内部完成 probing / retry / failover。

优点：

- 调用点表面更简洁；
- 下载入口看起来是“一次调用完成”。

缺点：

- service 需要知道 source 排序策略与失败分类，职责变重；
- 与 repository / task persistence / Riverpod invalidation 边界不清；
- 很容易把 infrastructure 变成 workflow 引擎。

### 方案 C：只补 UI 上的“自动切源”提示，不做真实 failover

做法：

- 页面写“失败后将自动尝试其他来源”；
- 但底层仍只会跑一个 source。

优点：

- 改动最少。

缺点：

- 是伪能力；
- 与 6-A 同类，都会制造语义欺骗；
- 不满足本轮“继续开发”的真实目标。

### 结论

本轮应采用 **方案 A：Controller 编排 + 轻量 Probe Helper**。

---

## 5. 推荐设计

### 5.1 分层职责

#### Application / Controller

`ModelDownloadController` 成为 6-B 的工作流拥有者，负责：

1. 组装 candidate sources；
2. 保证用户当前选中的 source 总是 first attempt；
3. 调用 probe helper 获取备用来源的临时排序依据；
4. 对单次 source 尝试结果做失败分类；
5. 在 source 之间切换时持久化各自的任务状态；
6. 当某个来源真正下载成功后，沿用现有 checksum → registry → runtime 校验主链。

#### Infrastructure / Probe

新增一个轻量探测服务，例如：

- `lib/features/ai_models/infrastructure/model_source_probe_service.dart`

它只负责：

1. 对一个 `ModelSourceEntry` 做轻量探测；
2. 返回 reachability / statusCode / contentLength / likely range support / latency 等瞬时事实；
3. 不做 persistence；
4. 不做 source 间 orchestration。

#### Infrastructure / Download

`ModelDownloadService` 继续保持单 source 下载原语，只负责：

1. `inspectDownloadTarget()`
2. 单一 URL 的 resume / restart
3. checksum 校验
4. 本地文件存在性 / 删除

它 **不** 负责：

1. 多 source 尝试顺序；
2. source failover 策略；
3. DB 任务状态更新；
4. UI 状态语义。

### 5.2 Candidate source 排序规则

6-B 的关键原则是：**手动选源不失效，但备用源可以更聪明地排序。**

推荐顺序：

1. **当前手动选中的 source 始终排第一**；
2. 对剩余 sources 并行做轻量探测；
3. 根据 probe 结果排序 fallback list；
4. 若 probe 无法区分优先级，则保持 catalog 原顺序。

排序维度从高到低：

1. reachable 优于 unreachable
2. content length 与预期更一致者优先
3. likely range support 优于 unknown / false
4. latency 更低者优先
5. catalog 原顺序作为最终 tie-breaker

### 5.3 Probe 机制

为保证最小改动，本轮采用两段式轻量探测：

1. **优先 HEAD**
   - 检查状态码；
   - 尝试读取 `content-length`；
   - 尝试读取 `accept-ranges`。

2. **HEAD 无效时再 fallback 到极小 GET / Range 探测**
   - 例如 `Range: bytes=0-0`；
   - 只用来判断 reachability 与 likely range support；
   - 不做真实下载 warmup。

探测超时需保持保守：

- connect / receive timeout 以“移动端轻量预探测”为准；
- 超时本身视为 source 不健康，但不应阻塞整个下载流程过久。

### 5.4 自动切源主流程

`ModelDownloadController.startDownload(entry, source)` 应扩展为以下语义：

1. 若模型已安装且本地文件存在，则直接返回；
2. 构建 `candidateSources`：
   - 第一个元素为当前 selected source；
   - 其余元素为 probe 排序后的 fallback sources；
3. 依次尝试每个 source：
   - 找到 / 创建该 `modelId + sourceId` 的 latest task；
   - 读取 target file 现状；
   - 计算本次 source 的 `resumeFromBytes`；
   - 更新该 source task 为 `downloading`；
   - 调用 `ModelDownloadService.download(...)`；
4. 若某个 source 成功：
   - 标记该 source task 为 `completed`；
   - 写入 registry；
   - 触发 embedding / llm runtime 验证；
   - invalidate 相关 providers；
   - 整个流程结束；
5. 若某个 source 失败且属于 failover-eligible：
   - 标记当前 source task 为 `failed`；
   - 错误文案可写为“当前来源失败，正在尝试其他下载源”；
   - 继续尝试下一个 source；
6. 若某个 source 失败且属于 terminal：
   - 标记当前 source task 为 `failed`；
   - 终止整个流程。
7. 若所有 source 都失败：
   - 最终暴露“所有可用下载源均失败”语义。

### 5.5 Resume 与 failover 的关系

这是 6-B 中最重要的安全边界。

#### 同 source retry

若本次尝试的 source 与 partial 文件对应的是同一 source：

- 继续沿用 6-A 的 resume 语义；
- `resumeFromBytes = inspectDownloadTarget(...).existingBytes`。

#### 跨 source failover

若从 source A 切换到 source B：

- **禁止复用 source A 的 partial bytes**；
- 本次 `resumeFromBytes = 0`；
- 若共享 target file 已存在，则在真正下载 source B 前删除该 target file；
- 不做“跨 source 共享 checksum 一样所以可续传”的推断。

原因：

1. 当前 target file 命名不是 source-specific；
2. partial 文件只按路径存在，不按 source 隔离；
3. checksum 只在完整下载后校验，无法证明 partial 兼容性。

### 5.6 失败分类

失败分类位于 controller / application policy 层，不下沉为大而全的全局异常体系。

#### Failover-eligible

以下错误应尝试下一 source：

1. connect timeout / receive timeout
2. DNS / socket / transient network failure
3. HTTP 5xx
4. HTTP 429 / rate limit
5. probe 明确不可达
6. checksum mismatch
7. 单一 source 返回的损坏响应

#### Terminal

以下错误应直接终止整次下载：

1. 用户主动 pause / cancel
2. checksum 缺失或格式不支持
3. malformed URL / catalog 数据本身错误
4. 本地文件系统错误
   - 无法创建 / 删除 / 写入文件
   - 存储空间不足
5. 下载已成功且 checksum 已通过后的 runtime 部署失败

最后一点非常重要：

- 一旦某 source 已完整下载并通过 checksum，source failover 已没有意义；
- 此时失败属于部署/runtime 问题，而不是镜像/source 问题。

### 5.7 页面语义

本轮 UI 只做最小必要修正，不新增复杂 visual state machine。

#### 保留

1. 当前 source dropdown
2. 当前来源文案
3. 下载任务状态卡
4. `开始下载 / 继续下载 / 重试下载 / 暂停` 语义
5. resumable / non-resumable 说明

#### 修正

页面不再只依赖 `_latestTaskFor(modelId)` 作为唯一任务来源。

需要区分两个概念：

1. **selected source task**：与当前 source 直接绑定，用于 pause / retry / source label / per-source status
2. **model display task**：用于状态卡 headline，优先展示当前活跃 source 的任务

推荐选择顺序：

1. `downloading`
2. `queued` / `paused` 且可恢复
3. 最新 failed
4. completed

若当前有 source B 正在下载，而手动选择仍停留在 source A，则状态卡和当前来源应优先反映 B，避免用户看到“下载失败”但实际上后台已自动切换成功。

#### 用户可见文案最小集

本轮足够的 UI 文案只有：

1. `当前来源失败，正在尝试其他下载源`
2. `所有可用下载源均失败`
3. 现有的 `断点续传：支持 / 当前下载源不支持`

不需要展示：

1. probe 分数
2. latency 数值
3. ranking 表格
4. 新的 `switching` 状态 enum

### 5.8 数据与持久化边界

本轮不新增任何数据库字段，也不改 `download_tasks` 表结构。

继续使用现有字段：

1. `sourceId`
2. `status`
3. `downloadedBytes`
4. `totalBytes`
5. `averageSpeed`
6. `errorMessage`
7. `resumable`

probe 结果全部为 **ephemeral state**：

- 只在单次下载工作流内使用；
- 不进入 SQLite；
- 不在页面上持久展示历史健康度。

---

## 6. 测试策略

本轮必须继续按 TDD 做，至少覆盖以下测试面：

### 6.1 Application 层

1. selected source 失败后 fallback source 成功；
2. fallback 到新 source 时 `resumeFromBytes` 被重置为 0；
3. 同 source retry 仍然沿用 6-A resume 语义；
4. checksum mismatch 会触发下一 source；
5. user cancel / pause 不触发 failover；
6. source-aware `markFailed` / `markCompleted` 只更新目标 source 的任务行；
7. 所有 source 都失败时，最终错误文案正确。

### 6.2 Infrastructure 层

1. probe 服务能识别 reachable / unreachable；
2. probe 在 `HEAD` 不可用时能 fallback 到极小 GET/Range；
3. probe 排序在信息相同情况下保持 catalog 原顺序稳定；
4. `ModelDownloadService` 既有 resume/restart 语义不被破坏。

### 6.3 Presentation 层

1. 页面状态卡优先显示当前活跃 source 的任务，而不是任意 model-level latest task；
2. selected source 的 source-specific 状态不会被其他 source 的旧任务污染；
3. source A stale failed + source B downloading 时，UI 能正确反映 source B；
4. 手动选源行为仍然可用，且自动切源不会让按钮/状态文案失真。

---

## 7. 风险与取舍

### 风险 1：跨 source 复用 partial 文件导致损坏

处理方式：

- 严格禁止跨 source resume；
- 一旦切源，强制从 0 开始。

### 风险 2：页面读取到错误 source 的任务

处理方式：

- source-specific 控件一律按 selected/active source task 取值；
- model summary task 使用更保守的优先级选择器。

### 风险 3：probe 逻辑过重，拖慢 happy path

处理方式：

- 只对 fallback list 做轻量排序；
- selected source 仍优先尝试；
- probe 只做低成本网络事实判断，不做完整 benchmark。

### 风险 4：把 strategy/state 持久化过早引入 schema 负担

处理方式：

- probe 结果全部保持内存态；
- 不新增 DB 字段。

---

## 8. 完成标准

当以下条件全部满足时，Milestone 6-B 可判定完成：

1. 用户选中的 source 失败后，系统能够自动尝试剩余 source；
2. fallback source 的顺序能够受轻量 probe 结果影响；
3. 同 source retry 仍可 resume；
4. 跨 source failover 不会错误复用 partial bytes；
5. controller 中 source-specific 状态更新不再落回 model-level latest task 假设；
6. 页面能正确显示当前活跃 source 的任务状态；
7. 所有新增 focused tests 通过；
8. `flutter analyze` 不引入新的错误。

---

## 9. 下一步边界

Milestone 6-B 完成后，Milestone 6 的后续推荐顺序为：

1. **Milestone 6-C：安装损坏探测 / 更强校验 / 签名校验**
2. **Milestone 6-D：设备能力检测 / benchmark / 推荐档位**
3. **Milestone 6-E：目录扩充 / 更多真实可发布模型资源**

这样可以继续保持每一轮只做一个清晰、可验证、低耦合的子闭环，而不是把整个模型下载系统一次性拉成高风险大改动。

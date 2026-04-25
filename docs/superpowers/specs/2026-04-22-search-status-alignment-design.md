# 搜索状态一致化设计

## 背景

当前 `SearchPage` 与 `SearchSettingsPage` 都会展示与语义检索、索引状态、下一步动作相关的信息，但两边的表达粒度和文案语义并不完全一致。

现状问题主要有：

1. 同一事实在两个页面里的表述方式不同，用户需要自行比对。
2. `SearchPage` 更偏结果工作面，`SearchSettingsPage` 更偏配置工作面，但两边都在解释“现在能不能用语义检索”。
3. 最近一次索引是否成功、是否需要首次构建、是否需要刷新索引，这些判断逻辑已经存在，但还没有统一成一套稳定的 UI 状态语言。

这会削弱 MVP 中“快速找回”和“渐进增强”的体验。用户可能知道“有语义检索”，但不清楚现在为什么不可用、应该去哪里处理、处理后是否已经恢复可用。

## 目标

在不扩张产品边界、不引入新页面、不重写搜索架构的前提下，统一 `SearchPage` 与 `SearchSettingsPage` 的搜索状态表达，让用户在两个页面里看到一致的：

1. 语义链路是否就绪
2. 当前索引是否需要首次构建
3. 当前索引是否需要刷新
4. 最近一次索引是否失败
5. 当前最合理的下一步动作是什么

本次设计只解决“状态一致化”和“动作一致化”，不解决自动轮询、后台任务编排、复杂错误恢复等后续能力。

## 非目标

本次不做以下事项：

1. 不新增自动刷新或轮询机制
2. 不引入新的后台索引调度器
3. 不扩展外部模型访问流程
4. 不重做搜索排序或结果融合逻辑
5. 不在 `SearchPage` 继续增加更多说明型卡片来堆叠信息

## 设计原则

### 1. SearchPage 强调行动，SearchSettingsPage 强调解释

- `SearchPage` 是主工作面，应优先告诉用户“现在能不能继续搜索”和“下一步做什么”。
- `SearchSettingsPage` 是解释与配置面，应展示更完整的状态背景和细节摘要。

### 2. 状态判断集中，页面只负责展示

现有页面中已经散落了一些 if/else 逻辑来判断：

- 是否有待索引项目
- 是否存在最近一次索引完成时间
- 是否有最近错误
- 是否已具备可用 embedding 模型

这些判断需要汇总为共享的 UI 摘要模型，避免两个页面分别维护一套近似但不完全相同的逻辑。

### 3. 文案统一，但不强制完全同形

两个页面对同一状态的标题、描述、CTA 语义应保持一致；
但由于页面职责不同，不要求视觉结构完全一致。

## 共享状态模型

新增一个轻量的搜索状态摘要层，用于把底层 provider 输出整理成页面可直接消费的状态。

建议抽象出以下信息：

### 基础字段

1. `headline`
   - 当前状态主标题，例如：
     - `本地语义链路未就绪`
     - `建议先构建本地索引`
     - `索引需要刷新`
     - `最近一次索引失败`
     - `本地语义检索已可用`

2. `description`
   - 当前状态的解释性文案

3. `pendingCount`
   - 当前待索引项目数量

4. `lastResultSummary`
   - 最近一次执行结果的摘要，例如成功处理了多少项、失败是否发生

5. `errorText`
   - 最近一次索引错误，若存在则用于强调展示

### 动作字段

1. `primaryActionLabel`
   - 主动作文案，例如：
     - `前往模型管理`
     - `立即构建索引`
     - `刷新索引`
     - `重试索引`

2. `primaryActionType`
   - 动作类型枚举，用于页面决定导航或触发控制器

### 状态枚举

建议统一成有限状态集合，而不是让页面继续直接依赖多个布尔组合：

1. `blocked`
   - 语义链路未就绪，需要优先解决模型/配置问题

2. `needsInitialIndex`
   - 语义链路基础条件已满足，但尚未完成首次索引

3. `needsRefresh`
   - 之前做过索引，但当前有新增/变更内容待处理

4. `lastRunFailed`
   - 最近一次索引失败，需要向用户强调风险与重试入口

5. `ready`
   - 当前可直接继续搜索，索引状态已最新

## 状态判定规则

为了避免歧义，本次明确使用以下优先级：

1. **blocked**
   - 条件：`!status.readyForIndexing`
   - 解释：当前没有满足本地语义索引执行的基本条件
   - 主动作：前往模型管理或搜索设置（优先前往模型管理）

2. **lastRunFailed**
   - 条件：`status.taskState.lastError != null`
   - 解释：即使当前模型可用，也要优先告诉用户最近一次失败，因为这是最需要处理的风险信息
   - 主动作：重试索引

3. **needsInitialIndex**
   - 条件：
     - `status.readyForIndexing == true`
     - `status.taskState.lastCompletedAt == null`
     - `status.pendingItems.isNotEmpty`
   - 主动作：立即构建索引

4. **needsRefresh**
   - 条件：
     - `status.readyForIndexing == true`
     - `status.taskState.lastCompletedAt != null`
     - `status.pendingItems.isNotEmpty`
   - 主动作：刷新索引

5. **ready**
   - 条件：
     - `status.readyForIndexing == true`
     - `status.pendingItems.isEmpty`
     - `status.taskState.lastError == null`
   - 主动作：无强制动作，SearchPage 只展示可继续检索；SearchSettingsPage 保留设置入口

## 页面落地方案

### SearchPage

`SearchPage` 中目前的 `_SemanticPipelineStatusCard` 与 `_SearchIndexHintCard` 会被收敛为围绕共享状态摘要展示的主状态卡。

该卡应做到：

1. 用统一 headline 告诉用户当前状态
2. 展示统一 description
3. 如有待索引项，展示 `待索引内容：N 项`
4. 如有最近错误，直接突出错误信息
5. 如有主动作，提供唯一主 CTA，避免同一屏出现多个相互竞争的状态动作

SearchPage 的状态卡应偏简洁，不再额外重复过多解释性文本。

### SearchSettingsPage

`SearchSettingsPage` 继续保留更完整的信息，但使用同一套 headline / description / action 语义。

具体表现为：

1. 顶部 readiness 区块与索引状态区块不再出现语义冲突
2. 最近结果摘要、错误信息、待索引详情仍然保留
3. 主 CTA 与 SearchPage 一致
4. 当状态为 `ready` 时，不再继续催促用户构建索引，而是强调“当前可直接使用语义检索”

## 动作映射

共享状态摘要只输出动作类型，实际页面行为如下：

1. `openModelManagement`
   - 跳转 `/models`

2. `openSearchSettings`
   - 跳转 `/search/settings`

3. `triggerIndex`
   - 调用 `searchIndexControllerProvider.indexPending()`

4. `none`
   - 不渲染主 CTA

这样可以保证：

- 判断逻辑在共享层统一
- 导航和控制器调用仍留在页面层完成

## 错误处理

本次错误处理坚持 MVP 保守策略：

1. 如果索引触发失败，仍沿用 SnackBar 反馈
2. 同时通过共享状态摘要在下次渲染时继续显式展示最近失败状态
3. 不做复杂错误分类，只展示已有 `lastError`
4. 不自动清空错误，除非下一次成功索引覆盖掉它

## 测试设计

本次必须补齐基于 widget 的状态回归测试，至少覆盖以下场景：

1. **blocked**
   - SearchPage 与 SearchSettingsPage 都显示“未就绪”语义
   - CTA 指向模型管理

2. **needsInitialIndex**
   - 两个页面都显示首次构建提示
   - CTA 为“立即构建索引”或等价统一动作文案

3. **needsRefresh**
   - 两个页面都显示刷新提示
   - CTA 为“刷新索引”

4. **lastRunFailed**
   - 两个页面都能看到最近失败语义
   - 错误文案可见
   - CTA 为重试索引

5. **ready**
   - 两个页面都不再展示“建议构建索引”之类的过时催促
   - SearchPage 更强调“现在可以继续搜索”

## 受影响文件

预计涉及：

1. `lib/features/search/application/search_providers.dart`
2. `lib/features/search/presentation/search_page.dart`
3. `lib/features/search/presentation/search_settings_page.dart`
4. 新增一个轻量状态摘要文件（放在 `application` 或 `presentation` 下均可，但应保持职责单一）
5. `test/features/search/presentation/search_page_test.dart`
6. `test/features/search/presentation/search_settings_page_test.dart`

## 默认假设

为保证 MVP 保守落地，本设计采用以下默认假设：

1. 当前“可否进行语义检索准备”的权威判断来自 `SearchIndexStatus.readyForIndexing`
2. “最近一次失败”比“当前有待索引内容”更应优先展示，因为它更直接影响用户对系统可用性的判断
3. `SearchPage` 与 `SearchSettingsPage` 可以共享状态语义，但不要求强制复用同一个大型 widget
4. 只要 `pendingItems.isEmpty` 且没有错误，就视为“当前已最新”，不额外引入更复杂的索引版本概念

## 预期结果

实现完成后，用户会获得更一致的体验：

1. 在搜索页能快速知道“能不能用”和“下一步做什么”
2. 在设置页能看到同样的状态语义，以及更详细的上下文解释
3. 同一类状态不会在两个页面中出现不同口径的描述
4. 当前搜索 / 索引主线在 MVP 范围内更完整，但不额外扩大系统复杂度

# 索引后自动刷新闭环设计

## 背景

当前 `SearchPage` 与 `SearchSettingsPage` 都已经支持触发索引动作：

1. `立即构建索引`
2. `刷新索引`
3. `重试索引`

并且在触发后会给出 SnackBar 反馈。

但当前流程仍存在一个明显断点：

1. 用户触发索引后，页面没有统一的“刷新中”过渡态。
2. `SearchPage` 与 `SearchSettingsPage` 之间不会共享这次刷新的视觉状态。
3. 搜索结果相关 provider 没有被统一刷新，因此用户可能仍然看到旧结果或旧状态。

这会让“索引动作是否真正生效”在 MVP 中显得不够完整。用户虽然看到了“已开始构建索引”的提示，但还需要依赖手动返回、再次进入页面或重新发起搜索来确认结果是否更新。

## 目标

在不引入复杂后台任务编排、不增加新页面、不做轮询系统的前提下，为索引动作补齐一个保守的自动刷新闭环：

1. 任一页触发索引后，两个页面共享“刷新中”状态
2. 按钮进入 loading/禁用状态
3. 状态卡展示明确的刷新中提示
4. 自动刷新搜索状态与搜索结果相关 provider
5. 刷新完成后自动退出刷新中状态，页面展示最新内容

## 非目标

本次不做以下事项：

1. 不实现后台轮询等待长任务完成
2. 不增加任务进度百分比
3. 不新增“索引中心”之类的页面
4. 不把索引任务状态扩展成通用任务系统
5. 不引入跨路由自动跳转或全局浮层流程

## 设计原则

### 1. 共享“刷新会话”而不是扩展“索引任务状态”

`SearchIndexTaskState` 当前表达的是索引任务本身的状态，例如：

- `running`
- `lastCompletedAt`
- `lastIndexedCount`
- `lastError`

而这次要补的是一个 UI 层的“刷新闭环”，它的职责是：

- 某次索引动作触发后，两个页面是否都应进入刷新态
- 搜索状态与结果是否处于重新拉取阶段

这与索引任务本身不是同一层语义，因此不应直接继续膨胀 `SearchIndexTaskState`。

### 2. 一个共享刷新状态，服务两个页面

本次新增一个轻量共享刷新状态，例如：

- `SearchRefreshSessionState`

它只负责表达：

1. 当前是否在进行索引后的 UI 刷新
2. 刷新提示文案
3. 最近一次刷新完成时间（可选）

`SearchPage` 与 `SearchSettingsPage` 都 watch 这一共享状态，因此无论用户在哪一页发起索引动作，两个页面都会同步进入刷新中视觉态。

### 3. 刷新动作保守地基于 provider invalidate

刷新闭环不通过额外数据层协议完成，而是继续沿用当前 Riverpod 模式：

在索引动作成功后，统一 `invalidate`：

1. `searchIndexStatusProvider`
2. `semanticSearchResultsProvider`
3. `unifiedSearchResultsProvider`

如有必要，也可以连带：

4. `keywordSearchResultsProvider`

但如果 `unifiedSearchResultsProvider` 已经依赖并覆盖关键词链路，本次优先只刷新最小必要集合。

## 共享刷新状态模型

建议新增：

### `SearchRefreshSessionState`

字段建议：

1. `refreshing`
   - 是否处于刷新中

2. `message`
   - 当前刷新提示，例如：`正在刷新搜索状态与结果...`

3. `lastCompletedAt`
   - 最近一次刷新完成时间，可选

该状态默认值为 idle：

- `refreshing = false`
- `message = null`
- `lastCompletedAt = null`

## 控制器设计

在现有 `SearchIndexController` 基础上新增一个更高层的方法，例如：

- `indexPendingAndRefresh()`

其职责分为两段：

### 第一段：执行索引

仍然沿用当前 `indexPending()` 的核心逻辑：

1. 读取当前 `searchIndexStatusProvider`
2. 验证 `readyForIndexing`
3. 读取模型与索引设置
4. 执行 `searchIndexServiceProvider.indexPendingItems(...)`
5. 更新 `searchIndexTaskStateProvider`

### 第二段：驱动共享刷新闭环

索引成功后：

1. 将 `SearchRefreshSessionState.refreshing` 设为 `true`
2. 设置提示文案为：`正在刷新搜索状态与结果...`
3. `invalidate` 相关 provider
4. 等待这些 provider 被重新读取完成
5. 将共享刷新状态恢复为 idle，并记录 `lastCompletedAt`

索引失败后：

1. 不进入成功刷新流程
2. 共享刷新状态回到 idle
3. 错误仍沿用现有 SnackBar 与 `SearchIndexTaskState.lastError`

## 页面行为

### SearchPage

`SearchPage` 中：

1. 状态卡读取共享刷新状态
2. 当 `refreshing == true` 时：
   - CTA 按钮进入 loading / disabled
   - 状态卡额外展示一行：`正在刷新搜索状态与结果...`
3. 当刷新完成后：
   - loading 结束
   - 统一结果区使用新 provider 结果重新渲染

### SearchSettingsPage

`SearchSettingsPage` 中：

1. 顶部 readiness 区块与中部索引状态卡都能感知共享刷新状态
2. 当 `refreshing == true` 时：
   - 所有索引动作按钮进入 loading / disabled
   - 状态卡展示刷新中文案
3. 刷新完成后：
   - 最新索引状态与最近结果摘要自动更新

## UI 要求

用户明确要求两种反馈同时存在，因此本次 UI 需包含：

### 1. 按钮内联 loading

当刷新会话正在进行时：

- 当前索引动作按钮禁用
- 文案可保留原动作名，配合 loading 指示器

### 2. 状态卡内刷新提示

在状态卡内部增加一行明确文本：

- `正在刷新搜索状态与结果...`

该提示在两个页面都应可见。

## 触发范围

用户已确认，本次采用跨页面联动：

1. 在 `SearchPage` 触发索引动作，`SearchSettingsPage` 也应感知刷新中状态
2. 在 `SearchSettingsPage` 触发索引动作，`SearchPage` 也应感知刷新中状态

这里的“联动”仅指共享刷新状态，不表示自动导航到另一个页面。

## 失败处理

本次失败处理沿用保守策略：

1. 索引失败时，仍显示现有 SnackBar：`索引触发失败，请稍后重试。`
2. 共享刷新状态必须及时退出，避免按钮卡死在 loading
3. `SearchIndexTaskState.lastError` 继续作为失败状态来源
4. 不新增独立的 refreshError 字段，避免状态模型重复

## 测试设计

本次至少补齐以下测试：

1. **SearchPage 触发后进入刷新态**
   - 按钮进入 loading/禁用
   - 卡片显示 `正在刷新搜索状态与结果...`

2. **SearchSettingsPage 触发后进入刷新态**
   - 按钮进入 loading/禁用
   - 卡片显示 `正在刷新搜索状态与结果...`

3. **共享刷新状态跨页面可见**
   - 两个页面都能消费同一共享刷新状态 provider

4. **成功后自动刷新 provider**
   - `searchIndexStatusProvider`
   - `semanticSearchResultsProvider`
   - `unifiedSearchResultsProvider`

5. **失败后退出刷新态**
   - loading 消失
   - 错误反馈仍存在

## 受影响文件

预计涉及：

1. `lib/features/search/application/search_providers.dart`
2. `lib/features/search/presentation/search_page.dart`
3. `lib/features/search/presentation/search_settings_page.dart`
4. `lib/features/search/presentation/search_status_summary.dart`（如需承接刷新提示）
5. `test/features/search/presentation/search_page_test.dart`
6. `test/features/search/presentation/search_settings_page_test.dart`

## 默认假设

为保持 MVP 保守实现，本设计采用以下默认假设：

1. 当前索引动作执行速度足够快，不需要后台轮询等待真正的长任务结束
2. provider invalidate + 重新读取 足以表达“刷新闭环”
3. 跨页面联动只需要共享刷新 UI 状态，不需要跨页面同步滚动位置或自动切页
4. 这次的刷新目标只覆盖搜索状态与结果，不额外扩展到模型页或其他功能页

## 预期结果

实现完成后，用户在任一搜索相关页面触发索引动作时，会获得一套更完整的闭环体验：

1. 按钮立即进入 loading
2. 状态卡明确提示系统正在刷新搜索状态与结果
3. 两个页面的视觉状态保持一致
4. 刷新结束后自动展示最新状态和结果
5. 不需要手动回退、重进或再次触发查询来确认本次索引是否生效

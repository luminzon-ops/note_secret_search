# 搜索刷新完成反馈增强设计

## 背景

当前搜索链路已经完成“索引触发 -> 共享刷新中状态 -> 自动刷新状态与结果 provider”的闭环：

1. `SearchPage` 与 `SearchSettingsPage` 会共享刷新中的视觉状态
2. 索引动作按钮会进入 loading / disabled 状态
3. 状态卡会展示 `正在刷新搜索状态与结果...`
4. `searchIndexStatusProvider`、`semanticSearchResultsProvider`、`unifiedSearchResultsProvider` 会在索引成功后自动刷新

但刷新完成后，用户仍然缺少一个明确答案：

1. 刷新是否真的完成了
2. 当前页面结果是否已经基于最新状态重算
3. 本轮刷新有没有改变当前查询结果

在 MVP 阶段，这会让“刷新完成”只能靠用户自己观察列表变化来推断，感知仍然偏弱。

## 目标

在不引入复杂 diff 面板、不增加任务中心、不重做搜索排序逻辑的前提下，为刷新完成补齐一层可解释反馈：

1. 明确告诉用户搜索状态已刷新
2. 明确告诉用户当前结果已经更新
3. 明确告诉用户本轮刷新是否影响当前结果
4. 当当前没有查询词时，仍给出保守且有用的完成反馈

## 非目标

本次不做以下事项：

1. 不展示逐条结果 diff
2. 不解释“新增了哪几条 / 消失了哪几条”
3. 不解释排序变化细节
4. 不增加全局消息中心或持久通知历史
5. 不让 `SearchSettingsPage` 承担主结果解释职责
6. 不增加后台轮询、进度百分比或任务编排系统

## 设计原则

### 1. 刷新完成反馈独立于刷新中状态

`SearchRefreshSessionState` 当前负责“刷新是否进行中”。

这次新增的能力是“刷新结束后应该如何向用户解释结果”，语义上属于一次刷新完成后的摘要，而不是进行中的会话状态。

因此不继续膨胀 `SearchRefreshSessionState`，而是新增独立的完成反馈状态，避免一个状态同时承担：

1. 进行中控制
2. 完成后摘要
3. 结果变化对比

### 2. 只比较最小必要信息

MVP 不做结果级 diff，只比较最小必要信息：

1. 当前 query 是否为空
2. 刷新前 unified results 的 id 顺序
3. 刷新后 unified results 的 id 顺序
4. 刷新前后的结果数量

只要这些信息足够判断“当前结果是否变化”，就不再向状态里塞入更复杂的数据结构。

### 3. 结果解释优先放在 SearchPage

`SearchPage` 是用户查看检索结果的主场景，因此刷新完成后的可解释反馈优先展示在这里。

`SearchSettingsPage` 仍保持：

1. 刷新中提示
2. 索引 readiness / status 摘要

但不承载完整的“结果变化解释”，避免设置页职责膨胀。

## 新增状态模型

建议新增一个共享 provider，例如：

- `searchRefreshFeedbackProvider`

对应状态模型例如：

- `SearchRefreshFeedbackState`

字段建议：

1. `visible`
   - 当前是否应该展示这次完成反馈

2. `headline`
   - 主文案，例如：`搜索状态已刷新`

3. `message`
   - 解释文案，例如：
     - `当前结果已更新，本轮刷新未改变当前结果。`
     - `当前结果已更新，结果数量从 2 条变为 5 条。`
     - `输入关键词后可查看最新结果。`

4. `changed`
   - 当前结果是否发生变化

5. `queryAtRefresh`
   - 生成该反馈时的 query，用于确保文案与当前上下文一致

6. `completedAt`
   - 最近一次反馈生成时间

默认值为隐藏状态：

- `visible = false`
- 其余字段为 `null`

## 刷新结果对比规则

本次采用最保守规则：

### 情况 A：当前 query 为空

反馈：

- headline：`搜索状态已刷新`
- message：`输入关键词后可查看最新结果。`

此时不判断结果变化，因为没有当前查询上下文。

### 情况 B：当前 query 非空，结果未变化

判断标准：

1. 刷新前后结果数量相同
2. 刷新前后结果 id 顺序完全相同

反馈：

- headline：`搜索状态已刷新`
- message：`当前结果已更新，本轮刷新未改变当前结果。`

### 情况 C：当前 query 非空，结果发生变化

只要以下任一条件满足即视为变化：

1. 结果数量变化
2. 结果 id 顺序变化

反馈优先级：

1. 若数量变化：
   - `当前结果已更新，结果数量从 X 条变为 Y 条。`
2. 若数量不变但顺序变化：
   - `当前结果已更新，本轮刷新调整了结果排序。`

## 控制器设计

在现有 `SearchIndexController.indexPendingAndRefresh()` 中补齐完成反馈逻辑：

### 刷新前采样

在真正 invalidate 前读取：

1. 当前 query
2. 当前 `unifiedSearchResultsProvider` 的结果列表

提取：

1. `beforeIds`
2. `beforeCount`

### 刷新后采样

在现有 refresh 流程完成后，再读取最新 `unifiedSearchResultsProvider` 结果并提取：

1. `afterIds`
2. `afterCount`

### 生成完成反馈

根据上述规则生成 `SearchRefreshFeedbackState`，并写入共享 provider。

索引失败时：

1. 不生成成功完成反馈
2. 将完成反馈状态恢复为隐藏
3. 仍沿用现有 SnackBar 与 `SearchIndexTaskState.lastError`

## 页面行为

### SearchPage

新增一个轻量“刷新完成反馈卡片”或“完成提示卡片”，放在状态卡下方、结果摘要上方。

展示规则：

1. `visible == true` 时展示
2. 刷新进行中不展示完成反馈
3. 若 query 已变化且与 `queryAtRefresh` 不一致，则隐藏这次旧反馈，避免误导

建议文案表现：

1. 标题：`搜索状态已刷新`
2. 正文：使用生成好的 `message`
3. 若 `changed == true`，可配合较积极的 icon，例如 `Icons.check_circle_outline`
4. 若 `changed == false`，可配合中性 icon，例如 `Icons.info_outline`

### SearchSettingsPage

本次不新增完整的结果变化说明卡。

设置页继续维持现有职责：

1. 管理设置
2. 展示索引 readiness / status
3. 展示刷新中状态

这样可以避免设置页与结果页职责混淆。

## 生命周期与隐藏策略

为了避免旧反馈长期停留，本次采用保守隐藏策略：

1. 新一轮索引刷新开始时，先清空旧完成反馈
2. 如果用户修改 query，且当前 query 与 `queryAtRefresh` 不一致，则 SearchPage 不再展示该反馈
3. 如果用户停留在当前 query，不自动清除，让用户能看到最近一次结论

## 测试设计

至少补齐以下测试：

1. **query 为空时生成完成反馈**
   - headline 为 `搜索状态已刷新`
   - message 为 `输入关键词后可查看最新结果。`

2. **query 非空且结果未变化时生成“未改变当前结果”反馈**
   - before / after 结果 id 相同
   - `changed == false`

3. **query 非空且数量变化时生成“结果数量变化”反馈**
   - before / after 数量不同
   - `changed == true`

4. **query 非空且数量不变但顺序变化时生成“排序调整”反馈**
   - before / after count 相同但 id 顺序不同
   - `changed == true`

5. **SearchPage 在刷新完成后展示反馈卡片**
   - headline / message 正确渲染

6. **SearchPage 在 query 已变化时隐藏旧反馈**
   - 避免用旧 query 的结论误导新 query

## 默认假设

1. “当前结果是否变化”以 unified results 为准，不单独对 semantic results 做额外解释。
2. 结果变化判断只依赖结果 id 与顺序，不比较 preview、score 或解释文案细节。
3. 只要用户当前 query 没变，最近一次刷新完成反馈就可以继续显示。
4. 本轮重点是把“刷新闭环”升级成“用户可感知闭环”，而不是进入搜索质量解释的下一阶段。

## 后续可扩展方向

如果后续需要继续增强，可以在下一任务中单独推进：

1. 展示新增 / 消失结果数量
2. 解释排序变化来自关键词还是语义链路
3. 把刷新完成反馈与搜索结果质量解释融合为更完整的结果说明层

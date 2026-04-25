# Query-Aware Semantic Ranking 设计

## 背景

当前 semantic candidate 的排序已经具备：

1. 字段质量分层优先
2. 同层按 score 排序
3. Top-K 截断前先保留高质量字段

但这仍然是“静态优先级”策略。对于某些 query 类型，用户真实意图会更偏向特定字段：

- URL-like query 更像在找网址/域名
- account-like query 更像在找账号/邮箱

如果仍然只按静态字段质量排序，可能会让 query intent 与结果排序不一致。

## 目标

在不改 unified fusion 结构的前提下，引入最小 query-aware semantic ranking，让 semantic candidate 更贴近当前 query 的意图。

## 方案

保持 `SemanticSearchService` 当前架构不变，只在 `search()` 的 candidate 排序阶段引入 query-aware 偏置。

排序优先级变为：

1. query-aware 字段意图匹配
2. 语义字段质量层级
3. semantic score

## Query Intent 规则

### URL-like query

满足任一条件即可视为 URL-like：

1. 包含 `.`
2. 包含 `://`
3. 包含 `/`

当 query 为 URL-like 时：

- `url` 字段命中获得 query-aware 优先级

### Account-like query

满足以下条件视为 account-like：

1. 包含 `@`

当 query 为 account-like 时：

- `username` 字段命中获得 query-aware 优先级

## 设计意图

1. query-aware 优先级只影响 semantic candidate 排序，不改变是否通过质量门槛
2. 仅覆盖最明显、最稳定的 query 类型，避免过度猜测
3. 继续保持实现简单，不引入复杂 NLP 或 query 分类器

## 非目标

本轮不做：

1. tag-like query 特殊处理
2. 多意图 query 混合策略
3. 修改 `SearchFusionService`
4. 修改 UI 文案
5. 修改 semantic quality 阈值

## 测试设计

至少覆盖：

1. URL-like query 会让 `url` 命中排到更高质量但非 URL 命中前面
2. account-like query 会让 `username` 命中排到更高质量但非 username 命中前面
3. 普通 query 仍保持当前静态字段质量排序

## 完成后的转向建议

这一轮完成后，更适合转向：

1. tag-like / label-like query 处理
2. semantic-only 结果的进一步过滤策略

不建议在这一轮继续扩展过多 query 类型，以免规则膨胀。

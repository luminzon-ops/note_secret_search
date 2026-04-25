# Tag-Like Query Semantic Ranking 设计

## 背景

当前 semantic candidate 排序已经具备：

1. URL-like query 优先 `url`
2. account-like query 优先 `username`
3. 否则回落到静态字段质量层级 + score

但对很多短标签式查询，例如：

- `backup`
- `finance`
- `work`

用户真实意图往往更接近“找某个标签命中的内容”，而不是“找正文里语义接近的摘要”。如果仍完全依赖静态字段质量层级，`summary` 这类高质量字段可能会一直压过 `tags`，导致 tag-like query 的结果排序不够贴近用户意图。

## 目标

在不改 unified fusion 结构和阈值的前提下，为 tag-like query 引入最小 query-aware semantic ranking，让 `tags` 命中在明显标签式查询下获得优先级。

## 方案

保持 `SemanticSearchService` 当前架构不变，只在 `search()` 的 candidate 排序阶段增加一种新的 query-aware 优先级：

1. URL-like query -> `url`
2. account-like query -> `username`
3. tag-like query -> `tags`
4. 再回落到字段质量层级
5. 最后再按 score 排序

## Tag-Like Query 规则

采用保守 MVP 规则。满足以下条件即可视为 tag-like：

1. query 不包含空格
2. query 不包含 `@`
3. query 不包含 `.`、`/`、`://`
4. query 仅由字母、数字、`-`、`_` 组成
5. query 长度较短（例如不超过 24）

## 设计意图

1. 只覆盖最明显的标签式查询，避免把普通自然语言 query 误判为 tag intent
2. `tags` 优先级只影响 semantic candidate 排序，不改变质量门槛
3. 保持实现简单，不引入复杂 query 分类器

## 非目标

本轮不做：

1. 多词标签 query 的特殊处理
2. 模糊 tag expansion
3. 修改 `SearchFusionService`
4. 修改 semantic quality 阈值
5. 修改 UI 文案

## 测试设计

至少覆盖：

1. tag-like query 会让 `tags` 命中排到静态高质量但非 tags 命中前面
2. 非 tag-like query 仍保持当前排序，不额外提升 `tags`

## 完成后的转向建议

这一轮完成后，更适合转向：

1. semantic-only 结果的进一步过滤策略
2. detail page 对 query-aware 命中的承接说明

# 语义召回 Top-K 策略优化设计

## 背景

当前 `SemanticSearchService.search()` 会把所有通过质量门槛的候选按 `score` 降序排序，然后直接 `take(5)`。

这意味着：

1. 即使上一轮已经收紧了弱字段阈值
2. 只要辅助字段命中数量足够多
3. 仍然可能在 Top-K 截断前挤掉高价值字段的较低分强语义命中

## 目标

在不改 unified fusion 架构的前提下，优化 semantic candidate 的 Top-K 截断策略，让：

1. `title / username / summary` 等高价值字段命中优先保留
2. `url / secretNote / tags / noteBody` 等辅助字段命中作为回填
3. 仍保持实现简单、可测、可解释

## 方案

保持现有 `SemanticSearchService` 结构不变，只调整 `search()` 中对 `candidates` 的排序规则：

1. 先按语义字段质量层级排序
2. 再按 `score` 降序排序
3. 最后保留前 `5` 条

## 分层规则

### 高质量语义字段

- `title`
- `username`
- `summary`

### 辅助语义字段

- `url`
- `secretNote`
- `tags`
- `noteBody`

## 设计意图

1. Top-K 是语义候选的“入场门”之一，不能只看分数
2. 质量分层优先于分数，更符合当前搜索解释体系
3. 不新增 query-aware 逻辑，不引入动态阈值

## 非目标

本轮不做：

1. 修改 `SearchFusionService`
2. 修改 `SemanticQualityPolicy`
3. 增加 UI 文案
4. 按 query 类型调整策略
5. 引入字段配额或复杂配比公式

## 测试设计

至少覆盖：

1. 当候选超过 5 条时，高质量字段命中应优先保留
2. 同一质量层内仍按分数排序
3. 当高质量候选不足时，辅助字段命中可以正常回填 Top-K

## 完成后的转向建议

这一轮完成后，更适合转向：

1. query-aware ranking / filtering
2. semantic-only 结果的更细粒度去噪

不建议继续只靠继续抬高全局阈值解决所有问题。

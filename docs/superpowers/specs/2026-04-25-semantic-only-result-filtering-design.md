# Semantic-Only Result Filtering 设计

## 背景

当前 unified result 的融合逻辑会：

1. 合并 keyword results
2. 合并 semantic results
3. 保留 dual-hit、keyword-only、semantic-only
4. 再做排序

虽然前几轮已经持续优化了：

- semantic quality threshold
- quality-aware top-k
- query-aware semantic ranking

但这仍然主要是在“让 semantic 结果更合理地排序”。对于 **semantic-only** 结果，当前仍缺少一层“是否值得展示”的融合层过滤。

## 目标

在不破坏 dual-hit 与 keyword-only 结果的前提下，对 semantic-only 结果增加最小展示过滤策略，减少低价值 semantic-only 项进入 unified results。

## 方案

过滤逻辑放在 `SearchFusionService`，只作用于：

- `matchSources == {semantic}` 的结果

### 保留条件

semantic-only 结果仅在满足以下条件时保留：

1. `semanticHitField` 属于高质量字段：
   - `title`
   - `username`
   - `summary`

或者：

2. `semanticScore >= 0.90`

### 过滤条件

以下 semantic-only 结果在未达到高分例外条件时应被过滤：

1. `url`
2. `secretNote`
3. `tags`
4. `noteBody`

## 设计意图

1. dual-hit 一律保留，不做过滤
2. keyword-only 一律保留，不做过滤
3. semantic-only 只有在字段质量足够高，或分数极强时才展示
4. 保持规则简单，不引入更复杂的 query-aware 过滤公式

## 非目标

本轮不做：

1. 修改 `SemanticSearchService`
2. 修改阈值策略
3. 修改 UI 文案
4. 动态 query-aware semantic-only 过滤
5. 不同字段使用不同 semantic-only 例外阈值

## 测试设计

至少覆盖：

1. semantic-only assist 字段且分数不够高时被过滤
2. semantic-only 高质量字段即使分数较低仍保留
3. semantic-only assist 字段在极高分时仍可保留
4. dual-hit assist 不被误过滤

## 完成后的转向建议

这一轮完成后，更适合转向：

1. detail page 对 semantic-only 命中的承接说明
2. search observability 中显示 semantic-only 过滤统计

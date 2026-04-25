# Semantic-Only 过滤原因说明设计

## 背景

当前 SearchPage 顶部观测摘要已经可以显示：

- semantic-only 候选数
- 最终保留数
- 过滤数

但用户和开发者仍然不知道“为什么这些 semantic-only 被过滤”。

## 目标

在不修改底层搜索服务返回结构的前提下，基于现有过滤规则为 observability summary 增加一条保守的“过滤原因提示”。

## 方案

继续在 presentation 层派生解释，不下沉到 service 层。

根据当前过滤规则，semantic-only 被过滤的主要原因可归纳为：

1. 命中字段属于辅助字段
2. 且 semantic score 未达到高分例外线（0.90）

因此 MVP 文案可统一为：

- `过滤原因：被过滤的 semantic-only 结果主要来自辅助字段，且分数未达到高分保留线。`

## 触发条件

仅当以下同时成立时显示：

1. `semanticOnlyFilteringBreakdown` 存在
2. 存在至少 1 条被过滤 semantic-only 候选

## 设计意图

1. 不做逐项过滤原因回溯
2. 不修改 `SearchFusionService` 返回调试信息
3. 用保守总括性文案先把过滤机制解释清楚

## 非目标

本轮不做：

1. 每条被过滤结果的逐项原因展示
2. 更细分的字段级过滤原因统计
3. 修改 result card 文案
4. 修改 filtering 规则本身

## 测试设计

至少覆盖：

1. helper 能在存在过滤时产出过滤原因文案
2. SearchPage expanded observability 能显示该文案
3. 没有过滤时不显示该文案

## 完成后的转向建议

这一轮完成后，更适合转向：

1. detail page 对 semantic-only 命中的承接说明
2. 更细粒度的 semantic-only 过滤原因统计

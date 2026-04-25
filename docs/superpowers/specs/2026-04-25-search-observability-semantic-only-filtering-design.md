# 搜索观测摘要中的 Semantic-Only 过滤统计设计

## 背景

当前搜索链路已经具备多层 semantic 质量控制：

1. semantic quality threshold
2. quality-aware top-k
3. query-aware ranking
4. semantic-only result filtering

但 SearchPage 顶部观测摘要还看不到最后这一步过滤是否发生，也不知道 semantic-only 项被过滤了多少。

## 目标

在 SearchPage 顶部观测摘要中补充 semantic-only 过滤统计，让用户和开发者能够知道：

1. 当前语义结果有多少条
2. unified result 中保留了多少 semantic-only
3. 有多少 semantic-only 在融合阶段被过滤掉

## 方案

不修改底层搜索逻辑，只在 presentation 层根据已有数据做派生统计：

1. `semanticResults` 提供语义候选总数
2. `unifiedResults` 提供最终保留的结果
3. 通过 id/type key 对比，统计最终保留的 semantic-only 数量
4. 差值作为过滤数量

## 统计口径

### semantic candidate count

来自 `semanticResults.length`

### kept semantic-only count

在 `unifiedResults` 中满足以下条件的数量：

1. `matchSources == {semantic}`

### filtered semantic-only count

通过以下方式计算：

1. 从 `semanticResults` 取出所有候选 key
2. 从 `unifiedResults` 取出所有 semantic-only key
3. `filtered = semanticCandidateCount - keptSemanticOnlyCount - dualHitSemanticCount`

但 MVP 中更简单可行的展示口径是：

- `semantic candidates X 条`
- `最终保留 semantic-only Y 条`
- `过滤 Z 条`

其中 `Z = semanticResults.length - unified semantic participants count` 会混入 dual-hit，不够准确。

因此本轮应采用 **semantic-only candidate count** 口径：

1. 在 presentation 层把 semanticResults 中“没有进入 dual-hit 的项”视为 semantic-only candidate
2. 再与 unified semantic-only 数量比较

## 文案方向

示例：

- `语义过滤：semantic-only 候选 3 条，保留 1 条，过滤 2 条。`

## 非目标

本轮不做：

1. 修改 `SearchFusionService` 返回结构
2. 修改 provider 层数据模型
3. 新增设置开关
4. 展示逐项过滤原因

## 测试设计

至少覆盖：

1. explanation helper 能产出 semantic-only 过滤统计文案
2. SearchPage 顶部观测摘要能显示该文案
3. 当没有 semantic-only 过滤发生时，不强制显示该文案

## 完成后的转向建议

这一轮完成后，更适合转向：

1. detail page 对 semantic-only 命中的承接说明
2. semantic-only 过滤原因的更细粒度解释

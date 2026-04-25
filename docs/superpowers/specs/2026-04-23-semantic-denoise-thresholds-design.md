# 语义召回去噪与阈值优化设计

## 背景

当前 placeholder semantic matching 已经具备基础质量门槛，但辅助字段仍然可能较容易通过：

- `url`
- `secretNote`
- `tags`
- `noteBody`

这会导致一些“有点像，但价值不高”的纯语义结果进入 unified result。

## 目标

进一步收紧 placeholder semantic matching，让辅助字段的弱语义召回更难进入结果。

## 方案

保持现有架构不变，只收紧 `SemanticQualityPolicy.minimumThresholdFor(...)`。

## 新阈值策略

基于 `minimumSemanticScore = 0.82`：

- `title` -> `0.82`
- `username` / `summary` -> `0.84`
- `url` / `secretNote` -> `0.87`
- `tags` / `noteBody` -> `0.90`

## 设计意图

1. 高价值字段仍然允许较积极召回
2. 辅助字段必须更强才进入结果
3. 不引入新的复杂 gate 公式

## 非目标

本轮不做：

1. 动态阈值学习
2. 基于 query 类型的门槛变化
3. 改写 fusion service
4. 调整 detail page 文案

## 测试设计

至少覆盖：

1. `title` 阈值仍相对宽松
2. `summary` 比 title 更严格
3. `url` / `secretNote` 比 summary 更严格
4. `tags` / `noteBody` 比 url / secretNote 更严格

## 完成后的转向建议

这一轮完成后，更适合转向：

1. semantic search top-K 策略优化
2. query-aware ranking / filtering

不建议只靠继续升阈值来解决所有语义噪声问题。

# Detail Page Semantic-Only Handoff 说明设计

## 背景

当前 detail page 在从搜索进入时，已经展示：

1. 命中方式
2. 查询词
3. 命中说明
4. 优先查看提示

但如果用户进入的是一个 **semantic-only retained result**，目前 detail page 不会额外说明“为什么这个结果虽然不是 keyword hit，仍然被保留下来”。

## 目标

在 secret / note detail page 的搜索 handoff card 中，为 semantic-only retained result 增加一条统一承接说明。

## 方案

MVP 继续使用现有路由参数：

- `searchSource == 'semantic'`

当 detail page 由 semantic-only 搜索结果进入时，追加一条说明文案，例如：

- `承接说明：该结果作为保留的语义命中进入详情页，建议结合命中字段与正文继续确认。`

## 设计意图

1. 不新增路由参数
2. 不区分 secret/note 的不同解释逻辑
3. 用一条统一文案先把 semantic-only retain 的含义承接下来

## 非目标

本轮不做：

1. 双命中详情页的额外说明
2. keyword-only 详情页的额外说明
3. 字段级保留原因展开
4. 修改底层搜索逻辑

## 测试设计

至少覆盖：

1. SecretDetailPage 在 semantic searchSource 下显示承接说明
2. NoteDetailPage 在 semantic searchSource 下显示承接说明
3. 非 semantic searchSource 不显示该说明

## 完成后的转向建议

这一轮完成后，更适合转向：

1. semantic-only retained 结果的字段级保留原因说明
2. search result card 与 detail page 承接文案统一化

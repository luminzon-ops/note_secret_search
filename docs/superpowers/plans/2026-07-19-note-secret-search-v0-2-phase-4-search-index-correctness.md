# Note Secret Search v0.2.0 Phase 4 搜索索引正确性实施计划

## 1. 基线与执行边界

本计划承接 `docs/2026-07-13-note-secret-search-v0-2-repair-roadmap.md`，从
Phase 3 最终提交 `04340cb71d3f6255b32f92d27474a2ea2ad0db97` 开始，在
`codex/repair-phase-4` worktree 中执行。

开始时重新核验的状态：

- 主工作树 `E:\Archive\Flutter\note_secret_search` 为
  `master @ 61a030bfa7da7dc42e2a7971a852be8950b40ecf`。
- 主工作树只保留用户修改的
  `lib/features/ai_models/presentation/model_management_page.dart`，以及
  `.agents/`、`.codex/`、`AGENTS.md`、
  `docs/2026-07-13-note-secret-search-v0-2-repair-roadmap.md` 未跟踪项。
- Phase 3 worktree 为干净的
  `codex/repair-phase-3 @ 04340cb71d3f6255b32f92d27474a2ea2ad0db97`。
- Phase 4 worktree 为
  `E:\Archive\Flutter\worktrees\note_secret_search-repair-phase-4`，
  分支为 `codex/repair-phase-4`，初始 HEAD 为 `04340cb`。

Phase 4 只处理搜索策略、索引数据、索引密钥、schema v6、检索融合和自动
AI 上下文。v5 中的旧 embedding 是可丢弃派生数据，迁移时清空，不转换旧
JSON vector，不恢复旧索引，也不改变 Secret、Note、聊天或模型业务数据。

明确不做：

- 不修改 `OnnxEmbeddingRuntime.kt`、`WordpieceEmbeddingTokenizer.kt`、
  ONNX 输出读取、pooling、线程模型、session cache 或其他 Phase 5 runtime。
- 不实现 Phase 6 的手动 AI 上下文内容扩展、外部 provider 授权和 prompt
  截断修复。
- 不改变模型下载、artifact、llama.cpp/AAR 或设备能力行为。
- 不用 UI 文案或测试替身宣称尚未实现的 runtime 能力。

## 2. 当前缺陷证据

实现前以代码和测试为准，路线图只作为范围约束。当前关键证据如下：

- `lib/features/search/domain/embedding_chunk.dart:6-29` 没有 Vault、字段、
  维度、配置、chunk、vector 或模型修订版本。
- `lib/features/search/application/search_index_service.dart:164-203` 先拼接
  多字段再切块，`semantic_search_service.dart:192-240,244-352` 通过列表位置
  猜测字段身份，导致 attribution 不可靠。
- `search_index_service.dart:257-259` 的 fingerprint 是可逆 Base64；
  `:105-115` 只要任一旧 chunk 命中就判定 source fresh；
  `sqlite_embedding_repository.dart:29-55` 逐块 REPLACE 而不删除缩短集合的
  尾块。
- `search_index_service.dart:65-96` 跨 source 聚合后一次写入，异常可留下
  部分来源；模型选择只失效 provider
  (`lib/features/ai_models/application/model_selection_providers.dart:21-32`)，
  旧模型集合仍可能保留。
- vector 写入为 UTF-8 JSON (`search_index_service.dart:86`)，读取直接
  `jsonDecode` (`semantic_search_service.dart:363-370`)；损坏 JSON 会中止
  查询，维度错误在 `:373-375` 静默记零。
- keyword (`search_service.dart:40-151`)、index 设置和 semantic
  (`semantic_search_service.dart:40-42`) 各自实现 scope；AI 自动检索继承
  semantic 缺陷，并在 `ai_chat_providers.dart:59-95,367-375` 只按裸 ID 去重。
- semantic 在融合前截断为 5 条 (`semantic_search_service.dart:49-73`)；
  threshold 实际比较加权分数 (`:214-216,411-413`)，UI 在
  `search_page.dart:643,726-730` 将其显示成相似度。
- Secret/Note provider 整库加载当前 Vault
  (`secret_providers.dart:12-23`、`note_providers.dart:12-23`)；semantic
  再逐 source 查 chunks (`semantic_search_service.dart:82-87,140-145`)；
  tag ID 超过 996 时 `sqlite_item_tag_store.dart:61-84` 退化为全库扫描。
- `database_schema_manager.dart:278-285` 只接受一条 ledger；v5 的
  `database_schema_v5.dart:111-124` 无法表达完整 generation。

上述缺陷在 Phase 4 测试中以生产 SQLite、真实 repository、policy、index、
semantic、fusion 和 AI retriever 路径复现，不以 mock-only 结果替代。

## 3. 领域术语、不变量与统一 scope

### 3.1 稳定领域术语

- `SearchSourceKey(type, id)`：`secret` 或 `note` 加稳定业务 ID。
- `SearchSourceField`：稳定字段身份和 source type 的绑定。
- `SearchOperation`：`keyword`、`index`、`semantic`、`aiAutoContext`。
- `EffectiveSearchPolicy`：当前 Vault、删除状态、字段 scope、password
  keyword opt-in、本地 embedding、自动 index 和 chunk 配置的单一有效策略。
- `EmbeddingIndexSet`：一个 source、Vault、model revision、configuration
  下的完整 generation，可为 zero-chunk。
- `EmbeddingChunk`：generation 内明确字段和 field-local index 的一个 vector。

### 3.2 稳定字段 ID

Secret 字段固定为：

`secret.title`、`secret.username`、`secret.password`、
`secret.website_url`、`secret.note`、`secret.tags`。

Note 字段固定为：

`note.title`、`note.summary`、`note.body`、`note.tags`。

数据库、canonical HMAC 和解释契约使用这些 ID，不使用可变 UI 文案。

### 3.3 Scope matrix

所有路径只接受当前 Vault、`deleted_at IS NULL` 的 source；semantic 和 AI
只接受当前 active embedding model 的精确 revision。最终去重键固定为
`(sourceType, sourceId)`。

| 字段/操作 | keyword | index | semantic | AI auto context |
| --- | --- | --- | --- | --- |
| Secret title | title 开关 | title 开关 | 同一 scope | 同一 scope |
| Secret username | username 开关 | username 开关 | 同一 scope | 同一 scope |
| Secret password | password opt-in | 永不 | 永不 | 永不 |
| Secret URL | URL 开关 | URL 开关 | 同一 scope | 同一 scope |
| Secret note | secret-note 开关 | 同一开关 | 同一 scope | 同一 scope |
| Secret tags | tags 开关 | tags 开关 | 同一 scope | 同一 scope |
| Note title | title 开关 | title 开关 | 同一 scope | 同一 scope |
| Note summary/body | `includeNoteBody` | 同一开关 | 同一 scope | 同一 scope |
| Note tags | tags 开关 | tags 开关 | 同一 scope | 同一 scope |

`secret.password` 仅在用户开启时参与 keyword，永远不进入 fingerprint、
embedding、semantic 或自动 AI context。`includeNoteBody` 同时控制
`note.summary` 与 `note.body`，设置 UI 政名为“笔记摘要与正文”。

`allowLocalEmbedding=false` 不影响 keyword；index 停止并批量清理，semantic
和 AI 返回空。external-provider 开关只控制既有外部隐私门，不进入本地
index hash。

## 4. 目标索引模型

`EmbeddingIndexSet` 持有：

- `sourceType`、`sourceId`、`vaultId`；
- `modelId`、`modelRevisionHash`；
- `sourceUpdatedAt`、`sourceFingerprint`；
- `fingerprintKeyId`、`fingerprintVersion`；
- `indexConfigVersion`、`indexConfigEpoch`、`indexConfigHash`；
- `chunkSchemaVersion`、`vectorFormatVersion`、`vectorDimension`；
- `chunkCount`、`createdAt`。

每个 `EmbeddingChunk` 持有：

- `indexSetId`；
- `sourceField`；
- `fieldChunkIndex`；
- `chunkFingerprint`；
- `vectorBlob`；
- `tokenCount`、`createdAt`。

每个 `(sourceType, sourceId, modelId)` 只有一个 active set；每个
`(indexSetId, sourceField, fieldChunkIndex)` 唯一；空字段不产 chunk，全部
字段为空仍提交 dimension=0、chunkCount=0 的 zero-chunk set。

## 5. Fingerprint、密钥与 canonicalization

Android 根主密钥通过独立 HKDF-SHA256 label
`note-secret-search/search-index-fingerprint/v1` 派生 32 字节 key。扩展
Kotlin unlock material、MethodChannel payload、Dart parser、
`DatabaseSessionKeys`、legacy migration clone 和 zeroization。现有 keyset
envelope 格式保持不变。

数据库只存 `fingerprintKeyId`、scheme version 和 HMAC 摘要；key 只存在已解锁
session。key ID 或版本变化使旧 generation 立即不可见并进入 purge，避免
固定 key、明文 key 和重启漂移。

HMAC canonical v1：

1. source 和 chunk 使用不同 domain tag；
2. 所有字符串 UTF-8、length-prefixed；
3. 整数和 byte length 使用 unsigned big-endian；
4. source 输入依次为 source type、source ID、Vault、固定字段顺序和字段值；
5. chunk 输入另含 field ID、field-local index 和 chunk text；
6. 文本将 CRLF/CR 规范化为 LF，去除首尾空白，保留内部内容和大小写；
7. tags 去空、ASCII-NOCASE 去重，以 NOCASE key 后 raw UTF-8 排序并逐项
   length-prefix。

`modelRevisionHash` 是 SHA-256 canonical v1，包含 registry id/type/provider/
version/quantization/verified checksum、按 role/sourceId 排序的 artifact
checksum、catalog tokenizer format/max length/lowercase/tokenizer asset SHA-256
及全部 runtime I/O/pooling/normalization 字段；排除本地路径、显示名和安装
时间。

## 6. Schema v6 与 migration/rebuild

schema 升级到 v6，v5 常量保持冻结。新增：

```sql
embedding_index_sets(
  id, source_type, source_id, vault_id, model_id, model_revision_hash,
  source_updated_at, source_fingerprint, fingerprint_key_id,
  fingerprint_version, index_config_version, index_config_epoch,
  index_config_hash, chunk_schema_version, vector_format_version,
  vector_dimension, chunk_count, created_at
)

embedding_chunks(
  id, index_set_id, source_field, field_chunk_index,
  chunk_fingerprint, vector_blob, token_count, created_at
)
```

`index_set_id` FK 为 `ON DELETE CASCADE`；CHECK 强制版本、非负计数、HMAC
32 字节、SHA-256 64 位小写 hex、非空 set dimension>0、zero-chunk set
dimension=0；trigger 校验 source 存在且未删除、Vault 一致、model type 为
embedding、字段属于正确 source type、blob 长度为 `dimension*4`。

source 内容、Vault、删除状态、tags 或 model revision 真实变化时，在原业务
事务内删除对应 set；password-only、favorite、category、last-accessed 不使
embedding 失效。

迁移策略：

- fresh-v6 先创建冻结 v5 baseline，再在同一 owner 中执行 v6 delta；
- v5→v6 丢弃旧 embedding 表并创建新表，不转换 JSON vector；
- v4→v6 在同一 `onUpgrade` 事务中先执行既有 v5 再执行 v6；
- ledger 固定为有序 v5、v6 两行，v5 checksum 不变；
- 每个 checkpoint 失败整体回滚，验证 `quick_check`、
  `foreign_key_check`、ledger、schema fingerprint、空 embedding 和无临时
  对象；
- v6 提交后 forward-only，不增加普通 downgrade。

## 7. Vector 与 per-field chunking

`float32-le-v1` 是无 header 的 IEEE-754 binary32 little-endian；dimension
位于 set，blob 长度精确为 `dimension*4`，所有值必须 finite，同 generation
维度一致，query 维度必须相同。

损坏、非 finite、count 不符或维度不符的 generation 单独排除，记录无
source ID、文本或 fingerprint 的原因计数，批量 purge 并标记重建，不中止
整次查询。

字段独立 chunk：

- title、username、URL、summary 等短字段通常一个 chunk；
- tags 每个规范化 tag 一个 chunk；
- note/body 按空段落累积；
- 超长段落按 Unicode scalar 边界硬切；
- 长度仅允许现有 UI 的 160/280/400；
- 字段顺序固定，`fieldChunkIndex` 每字段从 0 开始；
- password 不传给 chunker 或 embedding engine。

embedding 在事务外串行生成；写前验证全部 vector。每个 source/model 使用
短事务重新核对 source 存在性、Vault、删除状态、`updated_at`、model
revision 和 configuration epoch，再 delete-old + insert-set/chunks + count
验证。

## 8. 生命周期、stale purge 与性能

replacement 事务前后校验变化即回滚，旧完整 set 保留；进程中断只留下旧
完整 generation 或新完整 generation。rebuild 不先全库删除，逐 source 替换
且可重复恢复。

stale purge 每事务最多 100 sets；source page 128、ID/IN 批次 200，低于
SQLite 999 bind；compatible chunk 通过 join/keyset page 读取，Secret/Note
候选分批加载，禁止 source-level N+1 和全库无界 materialization。

invalidaton matrix：

| 变化 | 行为 |
| --- | --- |
| 可索引内容、tag、Vault、删除状态 | 当前 generation 删除，source 入重建队列 |
| model id/revision | 旧 model 集合不可见并 purge |
| scope、chunk length、schema/config version | epoch 增加，旧 config 不可见并 purge |
| fingerprint key id/version | 旧 key generation 不可见并 purge |
| password-only | keyword policy 变化时生效，不碰 embedding |
| favorite/category/last-accessed | 不使 embedding 失效，仅影响结果排序或业务视图 |
| 单个 corrupt generation | 排除、计数、purge、重建，不影响其他 generation |
| source 删除或 Vault 切换 | 同事务清理 set，查询 scope 立即排除 |

## 9. Ranking、fusion 与 explanation contract

chunk 先按 raw cosine threshold 过滤：

- title `.82`；
- username/summary `.84`；
- URL/secret-note `.87`；
- tags/body `.90`。

权重保持现有意图：title `1.16`、username/summary `1.10`、
URL/secret-note `1.04`、tags `.96`、body `.92`。source ranking score 是
最高两个 passing chunk weighted score 的平均值，最高 evidence 为 primary
field。

fusion 固定为 dual-hit > semantic-only > keyword-only；semantic-only assist
需要 aggregate ranking score `>=0.90`，dual-hit 只需通过字段 raw threshold。
最终 依次比较 fusion tier、query affinity、字段质量 tier、aggregate ranking
score、字段优先级、favorite、updatedAt，最后以 source type 和 source ID
升序稳定收尾。semantic 100 candidates、keyword 200、最终 100、AI 5。

`SearchEvidence` 暴露 kind、真实字段、summary、raw similarity、weight、
ranking score、threshold 和 generation version。keyword evidence 记录命中字段
但不保存命中明文。UI 只显示 primary raw similarity clamp 到 `[0,1]` 的
百分比；weighted/aggregate 明确显示为“排序分”。观察信息只显示字段分布、
版本和无敏感计数。

## 10. 文件级范围

主要范围：

- `lib/core/security/`：session key、HMAC、model revision canonicalizer；
- `lib/core/storage/database/`：schema v6、manager、repositories、triggers；
- `lib/features/search/domain/`：source/field/policy/index/vector/evidence 模型；
- `lib/features/search/application/`：policy、projector、chunker、index、
  semantic、fusion、purge；
- `lib/features/search/infrastructure/`：SQLite v6 adapters 和 paged readers；
- Secret/Note/AI model lifecycle 的失效入口、AI chat retriever；
- Android Kotlin key derivation/payload/zeroization；
- 对应 Dart/Kotlin tests、fixtures 和必要质量脚本配置。

继续保持文件小于 500 行，不修改 Phase 5 runtime/tokenizer/threading 文件。

## 11. RED→GREEN 实施顺序

- [ ] 建立并验证 worktree；提交本计划：
  `docs: add phase 4 search index correctness plan`。
- [ ] RED key derivation、payload、migration clone、zeroize、HMAC golden；
  GREEN 增加第三会话 key 与 canonical HMAC codec；提交
  `feat: derive search index fingerprint key`。
- [ ] RED fresh-v6、v5→v6、v4→v6、ledger、checkpoint rollback、重复打开、
  旧 JSON embedding 丢弃、constraints/trigger/query-plan；GREEN v6 delta 和
  manager；提交 `feat: migrate search index storage to schema v6`。
- [ ] RED field identity、generation invariant、float32 endian golden、损坏与
  维度错误；GREEN `EmbeddingIndexSet`、`EmbeddingChunk`、vector codec；提交
  `feat: define field aware embedding generations`。
- [ ] RED scope matrix、password keyword-only、summary/body 联动、保守迁移和
  中断重试；GREEN 加密 policy store、epoch、统一 policy、设置 UI；提交
  `fix: unify search scope policy`。
- [ ] RED source/chunk HMAC、tags canonicalization、字段顺序、Unicode chunk、
  model revision path independence/tokenizer digest invalidation；GREEN
  projector、chunker、revision resolver；提交
  `feat: build deterministic per field index inputs`。
- [ ] RED old-tail、zero-set、写入故障回滚、并发 source/model/config 变化和
  跨模型残留；GREEN per-source transactional replacement；提交
  `fix: replace embedding generations atomically`。
- [ ] RED content/tag/delete/Vault/model/config/key/version/corruption
  invalidation 与 purge 中断恢复；GREEN triggers、controller、batched purger；
  提交 `fix: purge stale search index generations`。
- [ ] RED production query-count、分页、200-ID batching、>999 fixture、无长
  事务；GREEN corpus/index keyset readers；提交
  `perf: page scoped search corpus reads`。
- [ ] RED attribution、raw threshold、权重、top-two、损坏隔离、deterministic
  semantic top-k；GREEN semantic read/ranking；提交
  `fix: rank semantic search from field evidence`。
- [ ] RED fusion tier、typed dedupe、排序收尾、raw-vs-ranking 展示和
  explanation versions；GREEN evidence-driven fusion/UI；提交
  `fix: make search fusion evidence based`。
- [ ] RED AI scope、password exclusion、typed same-ID Secret/Note、top-5 和
  corruption isolation；GREEN 复用统一 semantic policy/evidence；提交
  `fix: align ai context retrieval with search scope`。
- [ ] RED production index→SQLite→semantic→fusion→AI fixture；GREEN provider
  wiring，删除位置推断和 JSON vector 测试；提交
  `test: add phase 4 search integration gate`。

每项行为变化先有失败测试；每个垂直切片运行 focused tests、相关 broader
tests 和 `git diff --check` 后再提交。

## 12. Fixture 与测试矩阵

Fixture 覆盖 fresh-v6、v5 含旧 JSON embedding、v4、v1/v2/v3 经既有链路到
v6、每个 migration checkpoint 中断、repeated-v6、future/invalid schema，
以及完整字段、空字段、多 chunk、同 ID 跨类型、删除/Vault/model/config/key/
version/corrupt generation。

生产集成测试使用真实 schema manager、SQL repositories、policy store、index
service、semantic、fusion 和 AI retriever，仅在 `EmbeddingEngine` seam 注入
确定性向量；期望值使用手算向量和固定字节，不由实现反算。

聚焦测试包括：

- Kotlin/Dart key derivation、payload、zeroization、canonical HMAC；
- schema manager、ledger、migration rollback、constraint/trigger、query plan；
- vector codec、chunker、projector、model revision；
- policy migration、scope matrix、settings epoch；
- transactional replacement、stale purge、pagination、query count；
- semantic raw threshold/ranking、fusion/evidence、AI context；
- production SQLite index-to-search integration。

## 13. 门禁、恢复与验收

最终执行：

1. `scripts/quality/Invoke-QualityChecks.ps1`，继续使用 E 盘质量缓存；
2. `git diff --check`；
3. Android JVM tests、debug APK；
4. Huawei `SPN-AL00` API 29 instrumentation 全部测试与敏感 Logcat smoke。

验收必须证明：

- 字段归属、scope、残留清理、排序和解释均经过生产路径；
- replacement 失败保留旧完整 set；
- 配置切换后旧 set 立即不可见；
- 中断可续跑，重复 rebuild 第二次无写入；
- 单个损坏 generation 不影响其他结果；
- v5 旧 JSON embedding 只会被清空，不会被转换或恢复。

回滚与重复执行验证：

- 每个 v6 checkpoint 中断后数据库整体回到原 v4/v5；
- 重开重复执行保持版本、ledger、fingerprint 和空 embedding 不变；
- replacement 在生成阶段、提交前、提交后分别注入失败并确认旧/新集合
  始终完整；
- purge 中断后按批次重试，无重复副作用；
- Phase 4 worktree 最终干净，Phase 3 仍为干净 `04340cb`；
- 主工作树 HEAD、修改文件和全部未跟踪项与启动快照逐项一致；
- `git diff` 不包含 Phase 5 runtime、tokenizer、ONNX 输出或线程模型文件。


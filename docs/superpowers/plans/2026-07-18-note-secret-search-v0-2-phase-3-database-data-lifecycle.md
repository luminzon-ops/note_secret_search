# Note Secret Search v0.2.0 Phase 3 数据库与数据生命周期修复计划

## Summary

- 从 `3cea0f8` 创建 `codex/repair-phase-3` 和 `E:\Archive\Flutter\worktrees\note_secret_search-repair-phase-3`，先提交本计划，再修改生产代码。
- 目标数据库版本定为 **schema v5**。Phase 2 的 v1-v3 copy-and-swap 继续产出冻结的 v4；认证打开数据库时再执行唯一的 v4→v5 原子迁移，保持既有 native journal 和中断恢复兼容。
- Phase 3 只处理 schema、迁移、ownership、事务和残留数据；清空旧 embedding 属于派生数据清理，不执行 Phase 4 索引重建，也不修改 Phase 5 runtime。

## Baseline And Evidence

- 主工作树仍在 `61a030b`，用户的已修改文件及 `.agents/`、`.codex/`、`AGENTS.md`、roadmap 均保持原样。
- Phase 2 worktree 干净并停在 `3cea0f8`；Phase 3 分支和目录尚不存在。
- 复跑结果：`flutter analyze`、590 项 Dart 测试、Android JVM、debug APK 均通过。
- Huawei `SPN-AL00` 当前 instrumentation 为 13/14；唯一失败是设备缺少 GGUF fixture，数据库与安全 instrumentation 全部通过。最终门禁前恢复校验过的 GGUF，不弱化或跳过该测试。
- 主要缺陷证据：历史升级漏掉 `model_registry.integrity_status`；schema owner 分散在 `sqlcipher_database.dart` 与 `legacy_database_migrator.dart`；无 FK/业务唯一约束/生产索引；Secret/Note 存在 N+1、非事务软删除和 tag 残留；Vault provider 位于 Secrets；模型删除遗漏 artifacts。
- 系统盘仅约 0.22 GB，所有命令继续通过 `scripts/quality/Invoke-QualityChecks.ps1` 使用 E 盘缓存，不把 Phase 0 磁盘清理混入本阶段。

## Target Schema And Invariants

- 新增 `schema_migrations(version, name, checksum, applied_at)`；v5 打开时必须同时满足 `user_version=5`、ledger checksum 和 schema fingerprint。
- FK：Vault 子表→`vaults`；Secret/Note category→`categories ON DELETE SET NULL`；`item_tags.tag_id`→`tags`；embedding model→`model_registry ON DELETE CASCADE`；chat message→session `ON DELETE CASCADE`。
- Trigger：拒绝跨 Vault category、跨 Vault tag、指向缺失或已软删 item 的 tag/embedding 写入。
- Unique：单一默认 Vault；同 Vault category/tag 名称大小写不敏感唯一；embedding `(source_type, source_id, model_id, chunk_index)` 唯一；每种 provider 最多一个 enabled 配置。
- Index：Secret/Note active Vault 排序、tag 反向关联、embedding source/model、download model/source/update、model installed time、provider enabled/update、chat session/update 和 message/session/created。
- CHECK：布尔列、item/source type、模型 integrity、download status、chat mode/role/status。
- 数据库始终恰有一个默认 Vault；Secret、Note、Category、Tag 不得跨 Vault；父表写入不再使用 SQLite REPLACE。
- item 保存必须原子提交主行、tag 替换和旧 embedding 失效；软删除必须原子提交 tombstone、tag unlink、孤立 tag 回收和 embedding 删除。
- v5 迁移清空全部旧 `embedding_chunks`，后续由 Phase 4 重建。
- 模型安装的 task 与 registry 同事务提交；删除覆盖 `localPath`、全部 artifacts 和模型目录，随后同事务清理 registry、tasks 与该模型 embeddings。

## Migration State Machine

1. `version=0`：直接创建并验证 v5、ledger 和默认 Vault。
2. `version=1..3`：继续执行 Phase 2 journaled migration 到冻结 v4；完成后首次认证打开再迁移 v5。
3. `version=4`：在 sqflite 单一升级事务中依次执行 inventory、历史漂移修复、数据规范化、shadow-table rebuild、约束/index/trigger 创建、验证和 ledger 写入。
4. 任一 v4→v5 checkpoint 抛错或进程中断：DDL、数据、ledger 与版本号全部回滚；重开仍为 v4并从头安全重试。
5. `version=5`：只读验证 fingerprint、ledger 和 `PRAGMA foreign_keys=1`，不重复 bootstrap。
6. `version>5` 或 v5 fingerprint/ledger 不匹配：发布 `database_schema_unsupported` 或 `database_schema_invalid`，保持锁定，不做猜测式修补。
7. v4 清洗规则：`verified→valid`，非法 integrity→`unknown`；已知字符串数组 artifact 转为结构化路径；非法非空 artifact JSON 中止迁移。
8. 多默认 Vault 保留最早的现有默认项；无默认则选最早 Vault；空库创建 `default`。
9. 重名 tag 选最早 `(created_at,id)`，重名 category 选最小 `(sort_order,id)`，重指关联后删除重复项；无效 category 置空；悬空/跨 Vault tag link 和零引用 tag 删除。
10. Secret/Note 缺失 Vault 或 chat message 缺失 session 属于业务数据异常，迁移整体回滚并进入恢复状态，不删除业务行。

## Interfaces And File Scope

- `AppDatabase` 新增 `transaction<T>(Future<T> Function(DatabaseExecutor) operation)`；实现复用现有 generation lease，并在锁定、回滚和 stale result 情况下保持 Phase 2 语义。
- 新建唯一的 database schema manager，独占 `latestVersion=5`、fresh create、v4→v5、default Vault、ledger、fingerprint 和 postcondition；`SqlCipherAppDatabase` 只负责连接生命周期。
- 冻结生产 v4 DDL供 Phase 2 pending copier 使用；冻结测试侧 v1、v2、upgraded-v3、fresh-v3 及三种 v4 fixture，禁止再从当前 DDL 反向裁剪历史 schema。
- 从 `SecretRepository` 删除 `getDefaultVault()`；将同名 `vaultRepositoryProvider/defaultVaultProvider` 移到 `features/vault/application`，调用方只调整 import。
- 增加内部 SQLite tag store，供 Secret/Note 共用批量读取、规范化写入和孤立清理，不新增公开 TagRepository。
- 增加 `ModelLifecycleStore` 与可替换 `ModelArtifactStore`；文件删除失败时保留 registry 供重试，文件全部删除后再提交数据库清理。
- 核心改动集中在 `lib/core/storage/database/`、`lib/core/storage/migration/`、Vault/Secret/Note/Search/AI Models SQLite adapters、对应 tests/support 与 `.github/workflows/quality.yml`；所有文件保持 500 行以内。

## TDD And Commits

1. [ ] 创建 worktree，确认两棵工作树状态；保存本计划为 `docs/superpowers/plans/2026-07-18-note-secret-search-v0-2-phase-3-database-data-lifecycle.md`；提交 `docs: add phase 3 database lifecycle plan`。
2. [ ] RED：历史 fixture 独立性和 frozen-v4 copier 测试；GREEN：冻结 DDL 与 v4 fixture 谱系；focused/full tests；提交 `test: freeze historical database fixtures`。
3. [ ] RED：fresh-v5、缺列 v4、重复执行、未知版本与 fingerprint 测试；GREEN：schema manager、ledger、callbacks 和验证器；提交 `feat: add recoverable schema v5 migrations`。
4. [ ] RED：每个迁移 checkpoint 的回滚/重开测试及 dirty-v4 不变量测试；GREEN：规范化、shadow rebuild、FK、unique、CHECK、index、trigger；提交 `feat: enforce database ownership constraints`。
5. [ ] RED：REPLACE 级联回归、事务 lease/rollback、唯一默认 Vault 测试；GREEN：`AppDatabase.transaction`、真正 UPSERT、单一 bootstrap owner；提交 `refactor: centralize database bootstrap and vault ownership`。
6. [ ] RED：Secret/Note save、softDelete、失败注入、ownership 和残留清理；GREEN：共享 tag store 与完整事务；提交 `fix: make item lifecycle cleanup transactional`。
7. [ ] RED：列表 SQL 次数、排序、空 tag、类型与 Vault 隔离；GREEN：每类列表固定为 item 查询加一次批量 tag 查询；提交 `perf: batch load item tags`。
8. [ ] RED：模型安装 DB 回滚、全部 artifact 删除、部分文件失败、重复删除、task/registry/embedding 原子清理；GREEN：Model lifecycle/artifact stores；提交 `fix: make model lifecycle cleanup recoverable`。
9. [ ] RED/GREEN：v1、v2、upgraded-v3、fresh-v3 经 Phase 2 v4 再到 v5 的端到端 fixtures；更新 CI focused migration step；提交 `test: complete phase 3 database gate`。

## Fixture Matrix And Gate

- Fixtures：fresh-v5；v1；v2；upgraded-v3 缺 integrity；fresh-v3 含 `verified`；upgraded-v4 缺 integrity；fresh-v4；Phase-2-migrated-v4；dirty-v4；每 checkpoint interrupted-v4；repeated-v5；invalid/future schema。
- 每个升级断言业务 PK、Secret/Note NSSF bytes、时间戳、provider/sync/settings/chat、security metadata 和 canonical digest；允许的变化仅限明确规范化项及 embedding 清空。
- 固定执行 `PRAGMA quick_check`、`foreign_key_check`、table/index/trigger inventory、ledger/fingerprint 和生产查询 `EXPLAIN QUERY PLAN`。
- Focused：database/migration、Secret、Note、Vault、embedding、model lifecycle、DI/provider tests。
- Full：`scripts/quality/Invoke-QualityChecks.ps1`，随后 `git diff --check`。
- Device：恢复 checksum-verified GGUF 后在 Huawei `SPN-AL00` 运行 `:app:connectedDebugAndroidTest`，要求 14/14 与敏感 Logcat smoke 全部通过。
- 完成条件：Phase 3 worktree 干净；主工作树状态逐项与开始时一致；没有 Phase 4 schema 字段、索引重建、Phase 5 runtime 或其他后续阶段改动。

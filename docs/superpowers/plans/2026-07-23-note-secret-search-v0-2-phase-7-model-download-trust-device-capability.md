# Note Secret Search v0.2.0 Phase 7：模型下载、信任与设备能力

## 1. 基线、Checkpoint 与边界

- 基线：`951d0eb82e38ac44891439c1e2acb5663b71eb5d`。
- 分支：`codex/repair-phase-7`；worktree：`E:\Archive\Flutter\worktrees\note_secret_search-repair-phase-7`。
- Phase 3、4、5、6 worktree、主工作树及 `model_management_page.dart`、`.agents/`、`.codex/`、`AGENTS.md` 保持原样。
- 本计划单独提交，提交信息为 `docs: add phase 7 model trust plan`；之后按小步切片实施。
- Phase 7 不引入远程 catalog 更新，不重建或替换 Phase 6 AAR，不实现 mtmd/MiniCPM backend，不进行 Phase 8 架构重构。

## 2. 缺陷证据

- [built_in_catalog.json](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/assets/model_catalog/built_in_catalog.json:1) 是裸数组，无 envelope、版本或签名；[asset_model_catalog_repository.dart](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/lib/features/ai_models/infrastructure/asset_model_catalog_repository.dart:16) 直接解析并静默丢弃无效节点；[model_catalog_entry.dart](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/lib/features/ai_models/domain/model_catalog_entry.dart:121) 只解析签名字段，不验签。
- checksum 与 URL 同属未签名 source；BGE fallback 复用 digest，tokenizer 没有独立 digest。
- [model_download_service.dart](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/lib/features/ai_models/infrastructure/model_download_service.dart:76) 直接写最终路径；resume 没有 `If-Range`、ETag、Last-Modified 或 Content-Range 起点校验，`416` 和损坏修复不完整。
- [database_schema_v5.dart](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/lib/core/storage/database/database_schema_v5.dart:127) 与 [model_download_task.dart](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/lib/features/ai_models/domain/model_download_task.dart:10) 仍是单文件、单 checksum、无 staging/validator/install phase 的契约。
- [sqlite_model_registry_repository.dart](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/lib/features/ai_models/infrastructure/sqlite_model_registry_repository.dart:120) 将 `filePresent` 固定为 true；启动 adoption 仅凭 checksum 可重新启用，绕过 runtime validation。
- [model_lifecycle_controller.dart](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/lib/features/ai_models/application/model_lifecycle_controller.dart:23) 只释放 embedding session；Phase 6 LLM coordinator 尚未接入 artifact replace/delete。
- [DeviceProfilerPlugin.kt](E:/Archive/Flutter/worktrees/note_secret_search-repair-phase-6/android/app/src/main/kotlin/com/example/note_secret_search/DeviceProfilerPlugin.kt:30) 只返回首选 ABI；管理页仍使用静态占位卡。
- 当前 LLM AAR 只含 `arm64-v8a`，SHA-256 必须保持 `9583871b4179ae48ce3c57796fad21580167de4183ca6c28efdc2ed4724f9b41`。

## 3. Trust 与 artifact 数据契约

### 3.1 Signed catalog

- 将 asset 改为 signed envelope：`schema_version`、单调 `catalog_version`、`key_id`、`signature_algorithm: Ed25519`、`payload`、detached `signature`。
- 使用严格 JSON 解析和 RFC 8785/JCS canonical bytes；拒绝重复 key、未知算法、非法 base64、非整数 manifest 数值和 schema 外字段。
- 签名输入为 domain separator `NSS-MODEL-CATALOG-V1` 加 canonical envelope（不含 detached signature）。
- 使用现有 `pointycastle` Ed25519 verifier；公钥 keyring 编译进 Dart 常量，私钥只存在离线签名环境。
- key rotation 仅由 app release 更新内置 keyring；支持 active/overlap/revoked key，manifest 不得自行引入信任根。
- 持久化最高已接受 version、payload digest、key ID；同版本不同 digest、版本回退、revoked/未知 key 均保持未信任。回滚通过更高 catalog version 指向旧 release。

### 3.2 Artifact identity

- 将 `ModelSourceEntry` 拆为 `ModelArtifactSpec` 与 `ModelSourceSpec`。
- 每个 artifact 固定 `artifact_id`、`release_id`、`role`、`required`、规范化相对路径、`size_bytes`、独立 lowercase `sha256`、runtime/ABI 约束和 source 列表。
- source 只保存 `source_id`、URL、priority；所有 source 必须对应同一 signed artifact digest。
- tokenizer 等 bundled asset 也作为 required artifact，具有独立 signed digest。
- registry、repair、replace、delete、download 全部以 `model_id + release_id + artifact_id` 为 identity，移除聚合 checksum 作为完整性依据。

## 4. Schema v8 与安装 journal

- 新增 `model_catalog_state`：accepted version/digest/key/schema 与 minimum accepted version。
- 新增 `model_registry_artifacts`：model/release/artifact 主键、role、relative path、verified digest/size、source、verified time、state。
- 扩展 `download_tasks`：operation、generation、release/artifact identity、source URL、staging path、expected digest/size、ETag、Last-Modified、phase、retry reason、received bytes。
- 新增 `model_install_journal`：operation、model/release/generation、old/new revision、staging/target roots、phase、error code、timestamps。
- v7 旧字段保留兼容读取；新路径不把旧 `checksum`、`artifact_paths_json` 或旧 catalog rows 当作可信安装证明。
- 旧 registry 只有在与 signed catalog 精确匹配时才转换为 artifact rows；含糊路径/role/checksum 保留、置 `unknown/disabled`，等待显式 revalidate/repair。
- 旧 download task 只有 identity、size、signed digest 完整匹配才恢复，否则转 orphaned/paused；staging 文件永远不可直接 adoption。
- v7→v8、fresh v8、重复执行、每个 checkpoint 中断/重试均保持幂等，并保留 Phase 3/4/5 数据和索引契约。

## 5. Download、resume、failover 与 filesystem 状态机

状态机：

`queued -> probing -> downloading <-> paused -> verifying -> staged -> runtime_validating -> releasing_sessions -> installing -> committing -> completed`

异常进入 `retryable_failed`、`rollback_pending` 或 terminal `failed`；删除使用 `deleting`。

- 每个 model 使用 operation lock；每个回调携带 generation，晚到 progress/failure/completion 通过 CAS 丢弃。
- 网络内容只写 `models/<modelId>/.staging/<operationId>/<artifactId>.part`；最终 revision 使用 `models/<modelId>/revisions/<generation>/<relativePath>`。
- resume 必须同时满足本地长度、task metadata、artifact identity、expected size 和 validator；发送 `Range` 加 `If-Range`。
- 只接受 `206` 且 Content-Range 起点等于本地长度、总长度等于 signed size；ETag/Last-Modified 变化、缺失 validator、错误 `206`、`412`、`416` 或 Range 后 `200` 均截断 staging 并从零开始。
- 无远端 validator 的 partial 标记为不可恢复；切换 source 默认清除 partial，从零开始，并再次验证同一 signed digest。
- 网络错误、408、429、5xx、checksum/validator mismatch、403/404/410 可尝试其他 source；策略错误和 malformed manifest 直接 terminal failure。
- 所有 required artifact 逐项验证 size/digest 后，才进入 runtime preflight；任一 sidecar/tokenizer 损坏阻止发布。
- repair 只补齐损坏 artifact，并生成完整新 revision；不固定选择 `sources.first`。
- 新 revision 验证后原子 rename；DB transaction 与 filesystem 由 journal 衔接。崩溃恢复只完成已验证提交或清理新 revision，旧 revision 始终保留。
- delete 先 journal、释放 session、移入 model-owned trash，再 purge DB；重复 delete、残留 staging/trash 和部分失败均幂等可恢复。
- download/delete 复用 artifact store 的 root containment、resolved ownership、symlink/junction 防护；拒绝 `..`、绝对路径、分隔符变体、case collision、directory/link escape 和跨模型路径。

## 6. Native lifecycle、Device Profiler 与 MiniCPM

- 新增统一 `ModelSessionReleaser` seam，封装 embedding、LLM 及未来 multimodal coordinator，release 具备幂等语义。
- replace/delete 顺序固定为：停止 write fence、等待 embedding release、等待 LLM release、确认 descriptors/session 已关闭、再做 filesystem mutation。release 失败时旧文件、registry 和 journal 保持可恢复。
- staged runtime preflight 使用临时 session，验证后先 release，再 rename。
- Device Profiler 返回完整 `supportedAbis`、RAM、存储、SDK 和设备信息；纯 Dart assessment 只生成兼容性说明和默认推荐。
- 默认推荐依据 `minRamMb`、artifact size、存储余量和 manifest ABI 约束排序；profile 缺失时保留 catalog 顺序。Profiler 永远不写 `ready/enabled`，真实 checksum、文件、ABI/JNI 和 runtime load 仍是最终权威。
- 当前 LLM runtime supported ABI 为 `arm64-v8a`；`armeabi-v7a`、`x86_64`、`x86` fixture 返回稳定 unsupported，不触发 native load crash；Phase 6 AAR 内容与 hash保持不变。
- MiniCPM 在 signed catalog、provider、UI、download、registry adoption、Dart bridge、native runtime、instrumentation 各层保持隐藏/unsupported。真实 mtmd backend、完整 digest、ABI packaging 和真机 E2E 另立 Phase 8 计划。

## 7. 文件范围与 RED→GREEN 提交切片

主要范围：`lib/features/ai_models/{domain,application,infrastructure,presentation}`、`lib/core/storage/database/database_schema_v8*`、`assets/model_catalog`、`android/.../DeviceProfilerPlugin.kt`、必要的 lazy ABI guard、模型 fixture 和质量脚本。Phase 5 ORT、Phase 6 AAR 二进制及无关 UI 保持原样。

1. Trust RED：canonical bytes、签名篡改、错误 key/算法、回滚、同版本不同 digest；GREEN：`fix(ai): verify signed model catalog manifest`。
2. Artifact RED：重复 ID/role、缺 required digest、镜像 digest 不一致、tokenizer 缺 digest；GREEN：`feat(ai): add structured model artifact contract`。
3. Schema RED：fresh/v7→v8、旧 JSON、重复迁移、checkpoint recovery；GREEN：`feat(storage): add phase 7 model trust schema`。
4. HTTP RED：ETag/Last-Modified、If-Range、错误 Content-Range、200/412/416、断流和 failover；GREEN：`fix(ai): make model downloads validator-bound`。
5. Filesystem RED：多文件 staging、symlink/traversal、进程中断、旧 revision 保留；GREEN：`fix(ai): install model revisions atomically`。
6. Repair RED：只损坏 sidecar、重复 repair、完整 manifest cleanup；GREEN：`fix(ai): repair and replace model artifacts transactionally`。
7. Lifecycle RED：embedding/LLM active session、release 阻塞/失败、重复 release、replace/delete 顺序；GREEN：`fix(ai): release native sessions before model mutation`。
8. Device/ABI RED：profiler recommendation、runtime failure、ABI matrix、profile failure；GREEN：`feat(ai): connect device capability recommendations`。
9. MiniCPM RED：各层暴露尝试与 unsupported 状态；GREEN：`test(android): enforce model ABI and multimodal gates`。

每个切片先保留 failing RED 测试，再完成最小 GREEN 实现；切片后运行 focused tests、`git diff --check`、敏感日志和改动边界扫描。

## 8. 测试与门禁

- Dart：catalog verifier、artifact contract、SQLite v8、真实 loopback HTTP、断点恢复、failover、filesystem atomic install、symlink/traversal、repair/replace/delete、generation/CAS、session release、profiler recommendation、MiniCPM hidden matrix。
- JVM：DeviceProfilerPlugin、完整 ABI 集合、lazy native ABI guard、LLM/embedding release adapter、runtime validation invariant。
- Instrumentation：真实 MethodChannel profile、unsupported ABI 不崩溃、native session release 后 replace/delete、engine recreate 与 Phase 6 lifecycle/privacy 回归。
- ABI matrix：AAR/APK entry audit 加 arm64 supported 与非 arm64 unsupported fixtures；AAR provenance/hash 保持不变。
- 最终运行 `flutter analyze --no-pub`、全量 Dart tests、Android JVM tests、instrumentation Kotlin 编译、debug APK、`git diff --check`、敏感日志扫描、Phase 3/4/5 隔离、Phase 6 AAR provenance/hash、Phase 5 embedding/ORT，以及 resume/failover/signature/checksum/corruption-repair/multi-file-cleanup/ABI matrix 全部门禁。
- 受影响切片运行 focused/broader tests；昂贵 AAR、ORT、APK 与完整质量门禁只在最终收口阶段统一运行，未变化 artifact 沿用既有结果。
- Huawei SPN-AL00 API 29 是唯一真实设备门禁，覆盖 download/resume、runtime validation、LLM load/release、replace/delete、ABI 和日志；设备未连接时保持待执行，不重复探测、不使用替代设备结果。

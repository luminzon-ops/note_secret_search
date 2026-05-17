# MiniCPM-V 4.6 本地多模态 Runtime 设计

## 背景

MiniCPM-V 4.6 当前在模型管理页被标记为 `unsupported_runtime`，下载入口显示“当前版本尚不支持 multimodal_llm：需要专用 runtime 后才能下载部署”。用户明确选择的成功标准是：App 不仅要能下载和部署 MiniCPM-V 4.6，还要能在真机上完成本地多模态推理。

现有本地 LLM 链路是单文件文本 GGUF 设计：Dart `ModelRegistryEntry.localPath`、MethodChannel `modelPath`、Kotlin `LocalLlmRuntime.generateText(modelPath)`、`GgufLlamaCppBackend.load(File)`、`LlamaHelper.load(path)` 都只表达一个 GGUF 文件。MiniCPM-V 4.6 GGUF 部署需要主模型 `MiniCPM-V-4_6-Q4_K_M.gguf` 和视觉投影文件 `mmproj-model-f16.gguf`，并需要支持 llama.cpp mtmd / MiniCPM-V 4.6 的 native 后端。

## 目标

1. MiniCPM-V 4.6 在模型页不再作为 unsupported runtime 被禁用。
2. App 能下载、校验、落盘并登记 MiniCPM-V 4.6 的全部必需 artifact。
3. 只有主模型 GGUF 和 `mmproj` 都可用时，模型才显示为已部署且可推理。
4. Android 本地 runtime 能加载 `modelPath + mmprojPath`，并接收图片输入完成本地多模态推理。
5. 真机验收必须返回非空本地多模态回复，且 logcat 无 native crash、无 empty text、无 runtime unsupported 错误。

非目标：

- 不把 MiniCPM-V 4.6 伪装成普通 `llm`。
- 不通过云端 provider 或外部服务实现 MiniCPM-V 推理。
- 不把“能下载文件”当作最终完成标准。

## 外部模型要求

MiniCPM-V 4.6 GGUF 的本地推理要求：

- 主模型：`MiniCPM-V-4_6-Q4_K_M.gguf`
- 视觉投影：`mmproj-model-f16.gguf`
- llama.cpp 版本：需要包含 MiniCPM-V 4.6 / mtmd 支持的版本或等价 OpenBMB Android demo 分支
- Instruct 模型推理参数：`--reasoning off`
- 推理等价形态：

```bash
llama-mtmd-cli \
  -m MiniCPM-V-4_6-Q4_K_M.gguf \
  --mmproj mmproj-model-f16.gguf \
  --image input.jpg \
  --reasoning off \
  -p "Describe this image."
```

## 推荐方案

采用“正式多模态 runtime 通道”。`multimodal_llm` 作为与 `embedding`、`llm` 并列的模型类型保留。下载系统支持多 artifact，registry 支持记录主模型和辅助文件，Dart/Kotlin bridge 支持多模态请求，Android native 层新增或替换为支持 MiniCPM-V 4.6 的 llama.cpp mtmd backend。

## 数据模型设计

### Catalog

`assets/model_catalog/built_in_catalog.json` 中 MiniCPM-V 4.6 保留：

- `type: "multimodal_llm"`
- 两个 required sources：主 GGUF 和 `mmproj`
- 明确 runtime requirement，例如 `runtime: "llama_cpp_mtmd_minicpm_v46"`
- 明确部署规则：所有 required sources 完整后才 installed

不要将 `type` 改成 `llm`。这样 UI、下载状态和 runtime 分发可以准确表达模型能力。

### Registry

现有 `ModelRegistryEntry.localPath` 只能表示一个文件。需要扩展为 artifact-aware 结构，例如：

```dart
class ModelArtifactPath {
  final String role; // model, mmproj, tokenizer, etc.
  final String localPath;
}
```

`ModelRegistryEntry` 保留 `localPath` 作为主 artifact 兼容字段，同时新增 artifact 列表或 `auxiliaryPaths`。MiniCPM-V 4.6 的 registry 记录至少包含：

- `localPath`: 主模型 GGUF 路径
- `artifacts[role=model]`: 主模型 GGUF 路径
- `artifacts[role=mmproj]`: `mmproj-model-f16.gguf` 路径
- `runtimeType`: `multimodal_llm`
- `requiredRuntime`: `llama_cpp_mtmd_minicpm_v46`

### Download State

下载任务不能再假设一个 catalog entry 只有一个有效文件。需要支持 per-source 状态：

- pending
- downloading
- verified
- failed

聚合状态规则：

- 任一 required source 失败：模型部署失败，显示具体失败 source。
- 部分 required source 成功：显示“部分文件已下载，继续/重试”。
- 全部 required source verified：写入 registry，并进入 runtime readiness 检查。

## Runtime 设计

### Dart API

新增多模态推理请求，避免把图片能力塞进文本 `LlmInferenceRequest`：

```dart
class MultimodalLlmInferenceRequest {
  final ModelRegistryEntry model;
  final String prompt;
  final String imagePath;
  final int maxOutputTokens;
  final int contextLength;
  final bool reasoningEnabled; // MiniCPM-V 4.6 Instruct 固定 false
}
```

新增 bridge 方法：

- `inspectMultimodalModel`
- `ensureMultimodalModelReady`
- `generateMultimodalText`

payload 必须包含：

- `modelId`
- `modelPath`
- `mmprojPath`
- `imagePath`
- `prompt`
- `reasoningEnabled: false`
- generation config

### Kotlin API

新增 `MultimodalLlmRuntime` 或引入 `LocalLlmModelSpec`。推荐使用 spec 对象减少继续扩大长参数列表：

```kotlin
data class LocalLlmModelSpec(
    val modelId: String,
    val modelPath: String,
    val mmprojPath: String? = null,
    val runtimeType: String,
)
```

多模态后端接口需要表达图片输入：

```kotlin
interface MultimodalLlmBackend {
    fun load(spec: LocalLlmModelSpec): LocalLlmBackendSession
    fun generateFromImage(
        session: LocalLlmBackendSession,
        imagePath: String,
        prompt: String,
        config: LocalLlmGenerationConfig,
    ): LocalLlmGenerationResult
}
```

文本 GGUF 后端继续保留现有路径，避免影响 SmolLM2 / Qwen 当前稳定性。

### Native Backend

当前 `org.nehuatl.llamacpp.LlamaHelper.load(path)` 只接收一个路径，不足以支持 MiniCPM-V 4.6。实施时必须满足以下之一：

1. 替换或升级 AAR，使其提供 `modelPath + mmprojPath + imagePath` 的多模态 API。
2. 新增项目内 JNI/NDK binding，编译包含 MiniCPM-V 4.6 mtmd 支持的 llama.cpp。
3. 引入 OpenBMB Android demo 的支持分支作为 native backend 基础，并封装为项目内 `MultimodalLlamaCppBackend`。

任何方案都必须暴露等价于 `--mmproj`、`--image`、`--reasoning off` 的能力。

## UI 设计

模型管理页：

- MiniCPM-V 4.6 下载按钮启用。
- 显示两个 artifact 的下载/校验状态。
- 如果 native runtime 不可用，显示“模型文件已部署，但多模态 runtime 不可用”，不能显示为可推理。
- 如果文件和 runtime 都可用，显示“已部署，可本地多模态推理”。

问答页：

- 保留现有自由聊天文本 LLM 路径。
- 新增多模态问答入口或在自由聊天中加入图片附件能力。
- 选择 MiniCPM-V 4.6 时，必须允许用户选择图片后发送 prompt。
- 发送前校验：模型已部署、`mmproj` 存在、图片路径可读、runtime ready。

## 错误处理

错误必须可诊断，不使用泛化 unsupported 文案：

- 缺主模型：`MiniCPM-V 主模型文件缺失，请重新下载。`
- 缺 `mmproj`：`MiniCPM-V 视觉投影文件缺失，请重新下载。`
- runtime 不支持 mtmd：`当前 native runtime 不支持 MiniCPM-V 4.6 多模态推理，请更新 runtime。`
- 图片不可读：`无法读取图片，请重新选择。`
- native 生成为空：保留错误并采集 logcat，不能伪造成功。

## 测试计划

### 单元测试

- catalog 解析 MiniCPM-V 4.6 两个 required artifact。
- 下载控制器对多 artifact 聚合状态正确。
- registry 能保存和读取 `mmproj` artifact path。
- presentation formatter 对 `multimodal_llm` 显示可下载、可部署状态。
- bridge payload 包含 `modelPath`、`mmprojPath`、`imagePath`、`reasoningEnabled=false`。
- Kotlin runtime 在缺 `mmproj` 时返回明确错误。

### 集成测试

- 模拟两个文件下载成功后，MiniCPM-V 进入 installed 状态。
- 模拟只下载一个文件时，MiniCPM-V 不进入 installed 状态。
- 多模态 runtime ready 成功后，UI 显示可推理。

### 真机验收

在 Huawei `SPN_AL00` 或等价 Android 真机上：

1. 安装最新 APK。
2. 下载 MiniCPM-V 4.6 主模型和 `mmproj`。
3. 验证 app 私有目录中两个文件均存在。
4. 选择一张测试图片，发送短 prompt。
5. UI 出现非空本地回复。
6. logcat 无 `SIGABRT`、无 `Backend returned empty text`、无 runtime unsupported 错误。

## 风险与缓解

- 风险：当前 AAR 无 mmproj/image API。缓解：优先验证 AAR 能力；若不支持，直接走新增/替换 native backend，不在 Dart 层假装支持。
- 风险：MiniCPM-V 4.6 文件总量约 1.6GB，下载耗时长。缓解：复用断点续传和 per-source retry。
- 风险：设备内存不足。缓解：catalog 保留 `min_ram_mb: 6144`，runtime ready 前检查可用内存并提示。
- 风险：影响现有文本 LLM。缓解：文本 runtime 和多模态 runtime 分离，现有 SmolLM2/Qwen 测试必须继续通过。

## 验收标准

完成后必须满足：

- MiniCPM-V 4.6 不再显示 unsupported download gating。
- 双 artifact 下载、校验、落盘、registry 登记均通过。
- App 能加载 MiniCPM-V 4.6 主模型和 `mmproj`。
- App 能用本地图片和 prompt 获得非空本地多模态回复。
- 现有文本 LLM `/ai/chat` 不回退、不破坏。
- 所有相关 Flutter/Kotlin 测试通过，`flutter analyze` 通过，真机验收有日志/UI 证据。

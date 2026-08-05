# Note Secret Search

**移动端密码管理 / 私密备忘录应用**，当前发布版本为 `0.2.0+2`，支持本地 AI 语义检索与本地/外部问答。

## 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | Flutter (Dart) |
| 状态管理 | Riverpod |
| Android 原生 | Kotlin |
| 数据库加密 | SQLCipher |
| Embedding 推理 | ONNX Runtime Mobile |
| LLM 推理 | llama.cpp / GGUF（Android arm64 本地 runtime） |
| 路由 | go_router |
| 网络 | Dio |

## 功能

- **密码管理** — 新建/编辑/删除密码条目，标签分类，复制账号密码
- **私密文本笔记** — 轻量 Markdown 笔记，标签分类收藏
- **安全存储** — SQLCipher 全库加密，敏感字段二次加密，截屏保护
- **关键词搜索** — 标题/标签/内容全文检索
- **本地 AI 语义检索** — ONNX Runtime 驱动的 embedding 语义搜索
- **本地 LLM 问答** — llama.cpp GGUF 模型本地推理；v0.2.0 本地 runtime 仅覆盖 arm64
- **模型管理** — 内置模型目录、下载、断点续传、自动切源、校验
- **外部模型接入** — OpenAI 兼容 API / Ollama；Release 仅允许 HTTPS，Debug 仅允许 loopback HTTP
- **明确边界** — MiniCPM / 多模态未实现，不声明硬件级防护或远程同步能力

## 快速开始

### 环境要求

- Flutter 3.41.5
- Dart 3.11.3（随 Flutter 3.41.5）
- Android SDK 36
- Android target SDK 34
- JDK 17
- Gradle wrapper 8.11.1

### 依赖安装

```bash
flutter pub get
```

### 运行

```bash
# Debug 模式（开发用）
flutter run --debug

# 构建 Android debug / androidTest / release APK / release AAB（单次 Gradle DAG）
cd android
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:assembleRelease :app:bundleRelease --no-daemon --stacktrace
```

### 质量检查

```powershell
.\scripts\quality\Invoke-QualityChecks.ps1
```

CI 使用同一 release contract、Dart/JVM/static gates，并通过 `package-once` job 产出 debug APK、androidTest APK、unsigned release APK/AAB。后续 artifact audit、API 24/API 34 smoke、tag-only signing 和 draft release 均消费同一批 artifacts。

### 发布文档

- [CHANGELOG](CHANGELOG.md)
- [v0.2.0 Release Notes](docs/release/v0.2.0-release-notes.md)
- [Supported Devices](docs/release/supported-devices.md)
- [Threat Model](docs/release/threat-model.md)
- [Known Limitations](docs/release/known-limitations.md)
- [Release Ledger](docs/release/v0.2.0-release-ledger.md)

### 下载安装包

最新 APK 在 [GitHub Releases](https://github.com/luminzon-ops/note_secret_search/releases) 页面下载。

## 项目结构

```
lib/
  app/               # 路由、主题、依赖注入
  core/               # 错误处理、安全、网络、存储
  features/
    ai_chat/          # AI 问答（本地 LLM + 外部模型）
    ai_models/        # 模型目录与下载管理
    ai_providers/     # 外部 AI 提供商配置
    auth_security/    # 生物识别、PIN 解锁、应用锁
    notes/            # 私密笔记
    search/           # 关键词 + 语义搜索
    secrets/          # 密码条目管理
    settings/         # 设置页
    vault/            # 保险库
  shared/             # 共享组件
android/              # Android 原生插件（ONNX Runtime、llama.cpp）
assets/
  model_catalog/      # 内置模型目录 JSON + tokenizer
test/                 # Dart 测试
```

## 授权

本项目仅用于个人学习和研究目的。

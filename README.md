# Note Secret Search

**移动端密码管理 / 私密备忘录应用**，支持本地 AI 语义检索与问答。

## 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | Flutter (Dart) |
| 状态管理 | Riverpod |
| Android 原生 | Kotlin |
| 数据库加密 | SQLCipher |
| Embedding 推理 | ONNX Runtime Mobile |
| LLM 推理 | llama.cpp / GGUF |
| 路由 | go_router |
| 网络 | Dio |

## 功能

- **密码管理** — 新建/编辑/删除密码条目，标签分类，复制账号密码
- **私密文本笔记** — 轻量 Markdown 笔记，标签分类收藏
- **安全存储** — SQLCipher 全库加密，敏感字段二次加密，截屏保护
- **关键词搜索** — 标题/标签/内容全文检索
- **本地 AI 语义检索** — ONNX Runtime 驱动的 embedding 语义搜索
- **本地 LLM 问答** — llama.cpp GGUF 模型本地推理，支持自由聊天
- **模型管理** — 内置模型目录、下载、断点续传、自动切源、校验
- **外部模型接入** — OpenAI 兼容 API 接口（Ollama/Anthropic/自定义 Endpoint 扩展预留）

## 快速开始

### 环境要求

- Flutter SDK 3.x
- Android SDK 34+
- JDK 17

### 依赖安装

```bash
flutter pub get
```

### 运行

```bash
# Debug 模式（开发用）
flutter run --debug

# 构建 debug APK
flutter build apk --debug
```

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

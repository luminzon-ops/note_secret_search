# Android 原生桥接首轮占位说明

当前已落地的 Kotlin 文件：

- `android/app/src/main/kotlin/com/example/note_secret_search/MainActivity.kt`
- `android/app/src/main/kotlin/com/example/note_secret_search/NativeSecurityPlugin.kt`
- `android/app/src/main/kotlin/com/example/note_secret_search/BiometricAuthenticator.kt`
- `android/app/src/main/kotlin/com/example/note_secret_search/SecureKeyManager.kt`

## 第一阶段已覆盖的桥接职责

1. `FLAG_SECURE` 截屏保护入口
2. Root Key 初始化占位
3. 生物识别可用性检测
4. Flutter `MethodChannel` 安全通道骨架

## 后续继续补充的 Kotlin 模块

### 1. Keystore / StrongBox
- 生成硬件保护 Root Key
- 包装 DEK
- 与 PIN 派生密钥做双门控解封装

### 2. SQLCipher Bridge
- 如果 `sqflite_sqlcipher` 生态不满足需求，则转为 Android 原生 DB 服务
- 对外提供打开数据库、迁移、事务与备份接口

### 3. Device Profiler
- RAM / CPU / ABI / Storage / Thermal / Battery / 可检测 GPU/NPU
- 生成设备档位推荐

### 4. Model Runtime
- ONNX Runtime Mobile embedding
- llama.cpp + GGUF 推理桥接
- 本地 benchmark 接口

### 5. Downloader
- WorkManager 后台下载
- 断点续传
- 多源切换
- checksum 校验

## Flutter 侧已预留对应入口

- `lib/features/auth_security/infrastructure/native_security_bridge.dart`
- 后续可按模块继续扩展 `MethodChannel` 或拆成多插件通道

## 默认假设

1. 首版 Android `minSdk` 为 24
2. 生物识别优先，PIN 后续作为二级备用门禁接入
3. 首轮只搭桥，不宣称已完成真实硬件级密钥保护

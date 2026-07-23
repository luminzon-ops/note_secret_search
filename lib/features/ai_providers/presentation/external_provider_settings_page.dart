import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

class ExternalProviderSettingsPage extends ConsumerStatefulWidget {
  const ExternalProviderSettingsPage({super.key});

  @override
  ConsumerState<ExternalProviderSettingsPage> createState() =>
      _ExternalProviderSettingsPageState();
}

class _ExternalProviderSettingsPageState
    extends ConsumerState<ExternalProviderSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _baseUrlController = TextEditingController(
    text: 'https://api.openai.com/v1',
  );
  final _apiKeyController = TextEditingController();
  final _modelNameController = TextEditingController();
  final _embeddingModelNameController = TextEditingController();
  bool _allowSensitiveFields = false;
  bool _enabled = false;
  bool _saving = false;
  bool _testing = false;
  bool _updatingPrivacy = false;
  ExternalProviderConfig? _loadedConfig;
  ExternalProviderType _providerType = ExternalProviderType.openAiCompatible;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadExistingConfig);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelNameController.dispose();
    _embeddingModelNameController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingConfig() async {
    final configs = await ref.read(externalProviderConfigsProvider.future);
    if (!mounted || configs.isEmpty) {
      return;
    }
    final config = configs.where((item) => item.enabled).firstOrNull ??
        configs.first;

    _displayNameController.text = config.displayName;
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelNameController.text = config.modelName;
    _embeddingModelNameController.text = config.embeddingModelName ?? '';

    setState(() {
      _loadedConfig = config;
      _enabled = config.enabled;
      _allowSensitiveFields = config.allowSensitiveFields;
      _providerType = config.providerType;
    });
  }

  void _onProviderTypeChanged(ExternalProviderType? type) {
    if (type == null) return;
    setState(() {
      _providerType = type;
      if (type == ExternalProviderType.ollama) {
        if (_baseUrlController.text == 'https://api.openai.com/v1') {
          _baseUrlController.text = 'http://localhost:11434';
        }
        if (_modelNameController.text.isEmpty) {
          _modelNameController.text = 'llama3';
        }
        if (_displayNameController.text.isEmpty) {
          _displayNameController.text = 'Ollama 本地服务';
        }
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      final controller = ref.read(externalProviderSettingsControllerProvider);
      final config = _buildConfig();
      await controller.save(config);
      if (!mounted) {
        return;
      }
      setState(() => _loadedConfig = config);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('外部模型配置已保存')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _disable() async {
    final persisted = _loadedConfig;
    if (persisted == null) {
      return;
    }
    setState(() => _updatingPrivacy = true);
    try {
      final config = persisted.copyWith(
        enabled: false,
        updatedAt: DateTime.now(),
      );
      await ref
          .read(externalProviderSettingsControllerProvider)
          .setEnabled(config, enabled: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _enabled = false;
        _loadedConfig = config;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('外部 AI 已停用')));
    } finally {
      if (mounted) {
        setState(() => _updatingPrivacy = false);
      }
    }
  }

  Future<void> _revokeConsent() async {
    final persisted = _loadedConfig;
    if (persisted == null) {
      return;
    }
    setState(() => _updatingPrivacy = true);
    try {
      await ref
          .read(externalProviderSettingsControllerProvider)
          .revokeConsent(persisted);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('外部发送确认已撤销')));
    } finally {
      if (mounted) {
        setState(() => _updatingPrivacy = false);
      }
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _testing = true);
    try {
      final controller = ref.read(externalProviderSettingsControllerProvider);
      await controller.testConnection(_buildConfig());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('连接测试成功')));
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  ExternalProviderConfig _buildConfig() {
    return ExternalProviderConfig(
      id:
          _loadedConfig?.id ??
          (_providerType == ExternalProviderType.ollama
              ? 'ollama-default'
              : 'openai-compatible-default'),
      providerType: _providerType,
      displayName: _displayNameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      modelName: _modelNameController.text.trim(),
      embeddingModelName: _embeddingModelNameController.text.trim().isEmpty
          ? null
          : _embeddingModelNameController.text.trim(),
      enabled: _enabled,
      allowSensitiveFields: _allowSensitiveFields,
      createdAt: _loadedConfig?.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项不能为空';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外部模型配置')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<ExternalProviderType>(
              initialValue: _providerType,
              decoration: const InputDecoration(
                labelText: '提供商类型',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: ExternalProviderType.openAiCompatible,
                  child: Text('OpenAI 兼容接口'),
                ),
                DropdownMenuItem(
                  value: ExternalProviderType.ollama,
                  child: Text('Ollama 本地服务'),
                ),
              ],
              onChanged: _onProviderTypeChanged,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: '配置名称',
                border: OutlineInputBorder(),
              ),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                border: OutlineInputBorder(),
              ),
              validator: _requiredValidator,
            ),
            if (_providerType != ExternalProviderType.ollama) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                ),
                validator: _providerType == ExternalProviderType.ollama
                    ? null
                    : _requiredValidator,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _modelNameController,
              decoration: const InputDecoration(
                labelText: '聊天模型',
                border: OutlineInputBorder(),
              ),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _embeddingModelNameController,
              decoration: const InputDecoration(
                labelText: 'Embedding 模型',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _enabled,
              onChanged: _saving || _updatingPrivacy
                  ? null
                  : (value) => setState(() => _enabled = value),
              title: const Text('启用外部 AI'),
              subtitle: const Text('默认关闭；启用后发送前仍需按配置确认。'),
            ),
            SwitchListTile(
              value: _allowSensitiveFields,
              onChanged: (value) =>
                  setState(() => _allowSensitiveFields = value),
              title: const Text('允许外部模型接收私密上下文'),
              subtitle: const Text('默认关闭，首次发送时仍会二次确认。'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testing ? null : _testConnection,
                    child: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存配置'),
                  ),
                ),
              ],
            ),
            if (_loadedConfig != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _updatingPrivacy ? null : _disable,
                    icon: const Icon(Icons.block_outlined),
                    label: const Text('停用外部 AI'),
                  ),
                  TextButton.icon(
                    onPressed: _updatingPrivacy ? null : _revokeConsent,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('撤销发送确认'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

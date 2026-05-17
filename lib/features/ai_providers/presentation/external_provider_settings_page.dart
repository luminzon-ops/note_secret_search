import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

class ExternalProviderSettingsPage extends ConsumerStatefulWidget {
  const ExternalProviderSettingsPage({super.key});

  @override
  ConsumerState<ExternalProviderSettingsPage> createState() => _ExternalProviderSettingsPageState();
}

class _ExternalProviderSettingsPageState extends ConsumerState<ExternalProviderSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _baseUrlController = TextEditingController(text: 'https://api.openai.com/v1');
  final _apiKeyController = TextEditingController();
  final _modelNameController = TextEditingController();
  final _embeddingModelNameController = TextEditingController();
  bool _allowSensitiveFields = false;
  bool _saving = false;
  bool _testing = false;

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
    final config = await ref.read(enabledExternalProviderProvider.future);
    if (!mounted || config == null) {
      return;
    }

    _displayNameController.text = config.displayName;
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelNameController.text = config.modelName;
    _embeddingModelNameController.text = config.embeddingModelName ?? '';

    setState(() {
      _allowSensitiveFields = config.allowSensitiveFields;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      final controller = ref.read(externalProviderSettingsControllerProvider);
      await controller.save(_buildConfig());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('外部模型配置已保存')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接测试成功')),
      );
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  ExternalProviderConfig _buildConfig() {
    return ExternalProviderConfig(
      id: 'openai-compatible-default',
      providerType: ExternalProviderType.openAiCompatible,
      displayName: _displayNameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      modelName: _modelNameController.text.trim(),
      embeddingModelName: _embeddingModelNameController.text.trim().isEmpty
          ? null
          : _embeddingModelNameController.text.trim(),
      enabled: true,
      allowSensitiveFields: _allowSensitiveFields,
      createdAt: DateTime.now(),
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
            Text(
              'OpenAI 兼容接口',
              style: Theme.of(context).textTheme.titleMedium,
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
              ),
              validator: _requiredValidator,
            ),
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
              value: _allowSensitiveFields,
              onChanged: (value) => setState(() => _allowSensitiveFields = value),
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
          ],
        ),
      ),
    );
  }
}

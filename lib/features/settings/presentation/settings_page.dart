import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('安全与隐私'),
            subtitle: const Text('生物识别、PIN、隐私模式、剪贴板清理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/security'),
          ),
          ListTile(
            title: const Text('AI 设置'),
            subtitle: const Text('本地模型目录、下载来源与外部模型访问风险提示'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/models'),
          ),
          ListTile(
            title: const Text('外部模型'),
            subtitle: const Text('OpenAI 兼容接口、API Key 与外发风险控制'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/ai/providers'),
          ),
          ListTile(
            title: const Text('搜索与索引'),
            subtitle: const Text('检索范围、语义索引策略与搜索隐私控制'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/search/settings'),
          ),
          const ListTile(
            title: Text('同步设置'),
            subtitle: Text('首版先保留 SyncAdapter 与 WebDAV 接口扩展位'),
          ),
        ],
      ),
    );
  }
}

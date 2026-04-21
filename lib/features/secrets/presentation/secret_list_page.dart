import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/auth_security/presentation/security_status_card.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';

class SecretListPage extends ConsumerWidget {
  const SecretListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultAsync = ref.watch(defaultVaultProvider);
    final secretListAsync = ref.watch(secretListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('保险库')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SecurityStatusCard(),
          const SizedBox(height: 16),
          _VaultSummaryCard(vaultAsync: vaultAsync),
          const SizedBox(height: 16),
          _SecretListSection(
            secretListAsync: secretListAsync,
            cryptoService: ref.read(cryptoServiceProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/vault/secret/new'),
        icon: const Icon(Icons.add),
        label: const Text('新增密码'),
      ),
    );
  }
}

class _VaultSummaryCard extends StatelessWidget {
  const _VaultSummaryCard({required this.vaultAsync});

  final AsyncValue vaultAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vaultAsync.maybeWhen(
                data: (vault) => vault?.name ?? '默认保险库',
                orElse: () => '默认保险库',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('首版 UI 不暴露多保险库，但底层保留 vault_id。'),
          ],
        ),
      ),
    );
  }
}

class _SecretListSection extends StatelessWidget {
  const _SecretListSection({
    required this.secretListAsync,
    required this.cryptoService,
  });

  final AsyncValue<List> secretListAsync;
  final dynamic cryptoService;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: secretListAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('密码条目'),
                  SizedBox(height: 8),
                  Text('还没有保存的密码条目，点击右下角开始新增。'),
                ],
              ),
            );
          }

          return Column(
            children: [
              for (final item in items.cast<dynamic>())
                ListTile(
                  title: Text(item.title as String),
                  subtitle: Text(
                    cryptoService.decryptNullable(item.usernameCiphertext as List<int>?) as String,
                  ),
                  leading: Icon(
                    (item.favorite as bool) ? Icons.star_rounded : Icons.lock_outline,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/vault/secret/${item.id}'),
                ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(error.toString()),
        ),
      ),
    );
  }
}

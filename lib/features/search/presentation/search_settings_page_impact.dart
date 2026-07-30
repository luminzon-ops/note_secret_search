part of 'search_settings_page.dart';

class _SearchSettingsImpactPreviewCard extends StatelessWidget {
  const _SearchSettingsImpactPreviewCard({required this.preview});

  final SearchSettingsImpactPreview preview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview.headline,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(preview.description),
            if (preview.immediateItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('立即影响', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final item in preview.immediateItems) Text('• $item'),
            ],
            if (preview.reindexItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('需要重新索引', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final item in preview.reindexItems) Text('• $item'),
            ],
            if (preview.recommendation != null) ...[
              const SizedBox(height: 12),
              Text('当前建议', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(preview.recommendation!),
            ],
          ],
        ),
      ),
    );
  }
}

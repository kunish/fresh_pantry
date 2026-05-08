import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient_draft.dart';
import '../models/storage_area.dart';
import '../providers/ai_draft_provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/storage_labels.dart';

class IngredientDraftReviewScreen extends ConsumerWidget {
  const IngredientDraftReviewScreen({super.key, this.regenerate});

  /// Optional callback for "重新识别".
  final Future<void> Function()? regenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(aiDraftProvider).ingredientDrafts;
    if (drafts == null) {
      return const Scaffold(body: Center(child: Text('草稿已丢失')));
    }
    final selectedCount = drafts.where((d) => d.selected).length;

    return Scaffold(
      appBar: AppBar(title: const Text('审核识别结果')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: drafts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final d = drafts[i];
          final accent = d.selected ? const Color(0xFF0EA5E9) : Colors.grey;
          return InkWell(
            key: Key('ingredient_row_${d.id}'),
            onTap: () => ref.read(aiDraftProvider.notifier).updateIngredientDrafts([
              for (final e in drafts) e.id == d.id ? (e..selected = !e.selected) : e,
            ]),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: d.selected ? accent.withValues(alpha: 0.06) : Colors.grey.shade100,
                border: Border(left: BorderSide(color: accent, width: 3)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    d.selected ? Icons.check_box : Icons.check_box_outline_blank,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${d.quantity.value} ${d.unit.value} · '
                          '${d.category.value ?? ''} · '
                          '${storageLabelFor(d.storage.value ?? IconType.fridge)} · '
                          '${d.shelfLifeDays.value ?? '-'} 天',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (regenerate != null)
              Expanded(
                child: OutlinedButton(
                  key: const Key('ingredient_review_regenerate'),
                  onPressed: () => regenerate!(),
                  child: const Text('重新识别'),
                ),
              ),
            if (regenerate != null) const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('ingredient_review_confirm'),
                onPressed: selectedCount == 0
                    ? null
                    : () async {
                        final notifier = ref.read(inventoryProvider.notifier);
                        for (final d in drafts.where((d) => d.selected)) {
                          await notifier.add(d.toIngredient());
                        }
                        ref.read(aiDraftProvider.notifier).clear();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已添加 $selectedCount 项')),
                        );
                        Navigator.of(context).maybePop();
                      },
                child: Text('入库 ($selectedCount 项)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/ingredient.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../providers/inventory_provider.dart';
import '../utils/expiry_calculator.dart';

class _BatchItem {
  String name;
  String quantity = '1';
  String unit = '个';
  String category;
  IconType storage;
  int? shelfLifeDays;
  DateTime? expiryDate;

  _BatchItem({
    required this.name,
    this.category = FoodCategories.other,
    this.storage = IconType.fridge,
    this.shelfLifeDays,
    this.expiryDate,
  });
}

class BatchEntryScreen extends ConsumerStatefulWidget {
  const BatchEntryScreen({super.key});

  @override
  ConsumerState<BatchEntryScreen> createState() => _BatchEntryScreenState();
}

class _BatchEntryScreenState extends ConsumerState<BatchEntryScreen> {
  final _items = <_BatchItem>[];
  final _nameController = TextEditingController();

  static const _storageIcons = {
    IconType.fridge: Icons.kitchen,
    IconType.pantry: Icons.shelves,
  };
  static const _storageLabels = {IconType.fridge: '冰箱', IconType.pantry: '食品柜'};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addItem() {
    final raw = _nameController.text.trim();
    if (raw.isEmpty) return;

    final defaults = FoodKnowledge.lookup(raw);
    final now = DateTime.now();

    final item = _BatchItem(
      name: raw,
      category: FoodKnowledge.categoryFor(raw),
      storage: defaults?.storage ?? IconType.fridge,
      shelfLifeDays: defaults?.shelfLifeDays,
      expiryDate:
          defaults != null
              ? now.add(Duration(days: defaults.shelfLifeDays))
              : null,
    );

    setState(() => _items.add(item));
    _nameController.clear();
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _confirmClearAll() {
    if (_items.isEmpty) return;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '清空列表',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
            content: Text(
              '确定要清空所有 ${_items.length} 个食材吗？',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '取消',
                  style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _items.clear());
                },
                child: Text(
                  '清空',
                  style: GoogleFonts.manrope(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _saveAll() async {
    if (_items.isEmpty) return;

    final notifier = ref.read(inventoryProvider.notifier);
    for (final item in _items) {
      final freshness =
          item.expiryDate != null && item.shelfLifeDays != null
              ? expiryFreshness(
                expiryDate: item.expiryDate!,
                totalShelfLifeDays: item.shelfLifeDays!,
              )
              : 0.85;

      await notifier.add(
        Ingredient(
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          imageUrl: '',
          freshnessPercent: freshness,
          state: freshnessStateForExpiry(
            freshness: freshness,
            expiryDate: item.expiryDate,
          ),
          category: item.category,
          storage: item.storage,
          expiryDate: item.expiryDate,
          shelfLifeDays: item.shelfLifeDays,
          expiryLabel:
              item.expiryDate != null
                  ? '${daysUntilExpiry(item.expiryDate!)}天后过期'
                  : '新鲜',
        ),
      );
    }

    final count = _items.length;
    if (!mounted) return;
    Navigator.pop(context, count);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '购物归来',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空全部',
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          // Input bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addItem(),
                      style: GoogleFonts.manrope(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: '输入食材名称...',
                        hintStyle: GoogleFonts.manrope(
                          color: AppColors.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        prefixIcon: const Icon(
                          Icons.add,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _addItem,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add, color: AppColors.onPrimary),
                  ),
                ),
              ],
            ),
          ),

          // Item list
          Expanded(
            child:
                _items.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 64,
                            color: AppColors.onSurfaceVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '输入食材名称开始批量添加',
                            style: GoogleFonts.manrope(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _buildItemRow(
                          key: ValueKey('batch_${item.name}_$index'),
                          item: item,
                          index: index,
                        );
                      },
                    ),
          ),

          // Bottom save button
          if (_items.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _saveAll,
                    icon: const Icon(
                      Icons.check_circle,
                      color: AppColors.onPrimary,
                    ),
                    label: Text(
                      '全部保存 (${_items.length} 件)',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: AppColors.onPrimary,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemRow({
    Key? key,
    required _BatchItem item,
    required int index,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Index
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primaryFixed,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name & info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        _storageIcons[item.storage],
                        size: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _storageLabels[item.storage]!,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      if (item.shelfLifeDays != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${item.shelfLifeDays}天',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Category badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item.category,
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Delete
            GestureDetector(
              onTap: () => _removeItem(index),
              child: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/ingredient.dart';
import '../providers/inventory_provider.dart';
import '../providers/navigation_provider.dart';
import '../widgets/freshness_meter.dart';

class AddIngredientScreen extends ConsumerStatefulWidget {
  const AddIngredientScreen({super.key});

  @override
  ConsumerState<AddIngredientScreen> createState() =>
      _AddIngredientScreenState();
}

class _AddIngredientScreenState extends ConsumerState<AddIngredientScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _expiryController;

  String _selectedCategory = '乳制品与蛋类';
  double _freshnessPreview = 0.85;

  static const _categories = ['乳制品与蛋类', '新鲜蔬果', '食品柜常备', '肉类与海鲜', '香料与草本'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _quantityController = TextEditingController();
    _expiryController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _nameController.clear();
    _quantityController.clear();
    _expiryController.clear();
    setState(() {
      _selectedCategory = '乳制品与蛋类';
      _freshnessPreview = 0.85;
    });
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final quantity = _quantityController.text.trim();

    final ingredient = Ingredient(
      name: name,
      quantity: quantity.isEmpty ? '1' : quantity,
      unit: '份',
      imageUrl: '',
      freshnessPercent: _freshnessPreview,
      state: _freshnessPreview > 0.5
          ? FreshnessState.fresh
          : _freshnessPreview > 0.2
          ? FreshnessState.expiringSoon
          : FreshnessState.expired,
      category: _selectedCategory,
      expiryLabel: _expiryController.text.trim().isEmpty
          ? null
          : _expiryController.text.trim(),
    );

    ref.read(inventoryProvider.notifier).add(ingredient);

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加 "$name" 到库存'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    _resetForm();

    // Navigate to inventory tab
    ref.read(navigationProvider.notifier).state = 1;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            '策划您的食材库',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '添加新食材到您的收藏。每一次添加，都是迈向下一道美食杰作的一步。',
            style: GoogleFonts.manrope(
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Barcode Scanner
          _buildBarcodeScanner(),

          const SizedBox(height: 32),

          // Ingredient Name
          _buildLabel('食材名称'),
          const SizedBox(height: 8),
          _buildFilledInput(
            controller: _nameController,
            hintText: '例如：特级初榨橄榄油',
            fontSize: 18,
          ),

          const SizedBox(height: 28),

          // Category
          _buildLabel('分类'),
          const SizedBox(height: 8),
          _buildCategoryDropdown(),

          const SizedBox(height: 28),

          // Quantity
          _buildLabel('数量'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildFilledInput(
                  controller: _quantityController,
                  hintText: '0',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '单位',
                style: GoogleFonts.manrope(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Expiration Section
          _buildExpirationSection(),

          const SizedBox(height: 36),

          // Save Button
          _buildSaveButton(),
          const SizedBox(height: 16),

          // Discard Button
          _buildDiscardButton(),
        ],
      ),
    );
  }

  // ─── Sub-widgets ────────────────────────────────────────────────────

  Widget _buildBarcodeScanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.qr_code_scanner,
              color: AppColors.onPrimaryContainer,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '快速扫描条码',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '即时同步库存',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          bottom: BorderSide(color: AppColors.outline, width: 2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
          ),
          style: GoogleFonts.manrope(fontSize: 16, color: AppColors.onSurface),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: _categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _selectedCategory = v!),
        ),
      ),
    );
  }

  Widget _buildExpirationSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLabel('保质期'),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.onSecondaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '新鲜度提醒',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: const Border(
                bottom: BorderSide(color: AppColors.outline, width: 2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                ),
              ],
            ),
            child: TextField(
              controller: _expiryController,
              decoration: InputDecoration(
                hintText: 'mm/dd/yyyy',
                hintStyle: TextStyle(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GradientFreshnessMeter(percent: _freshnessPreview),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryContainer],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check_circle, color: AppColors.onPrimary),
          label: Text(
            '保存到收藏',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppColors.onPrimary,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscardButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _resetForm,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(
          '放弃更改',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ─── Shared helpers ─────────────────────────────────────────────────

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildFilledInput({
    required TextEditingController controller,
    String? hintText,
    double fontSize = 16,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          bottom: BorderSide(color: AppColors.outline, width: 2),
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.manrope(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          filled: false,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

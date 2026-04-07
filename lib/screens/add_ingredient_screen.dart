import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/ingredient.dart';
import '../models/storage_area.dart';
import '../data/food_knowledge.dart';
import '../providers/inventory_provider.dart';
import '../providers/navigation_provider.dart';
import '../widgets/shared/freshness_meter.dart';
import '../services/open_food_facts_service.dart';
import 'barcode_scanner_screen.dart';

class AddIngredientScreen extends ConsumerStatefulWidget {
  const AddIngredientScreen({super.key});

  @override
  ConsumerState<AddIngredientScreen> createState() =>
      _AddIngredientScreenState();
}

class _AddIngredientScreenState extends ConsumerState<AddIngredientScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;

  String _selectedCategory = '乳制品与蛋类';
  IconType _selectedStorage = IconType.fridge;
  String _selectedUnit = '个';
  int? _selectedShelfDays;
  DateTime? _selectedExpiryDate;
  int? _suggestedShelfDays;
  bool _autoFilled = false;
  String _resolvedImageUrl = '';

  static const _categories = ['乳制品与蛋类', '新鲜蔬果', '食品柜常备', '肉类与海鲜', '香料与草本'];

  static const _storageLabels = {
    IconType.fridge: '冰箱',
    IconType.pantry: '食品柜',
    IconType.freezer: '冷冻室',
  };
  static const _storageIcons = {
    IconType.fridge: Icons.kitchen,
    IconType.pantry: Icons.shelves,
    IconType.freezer: Icons.ac_unit,
  };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _quantityController = TextEditingController();
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // ─── Smart defaults ────────────────────────────────────────────────
  Future<void> _lookupImage(String name) async {
    if (name.length < 2) return;
    final result = await OpenFoodFactsService.searchByName(name);
    if (result?.imageUrl != null && mounted) {
      setState(() => _resolvedImageUrl = result!.imageUrl!);
    }
  }

  void _onNameChanged() {
    final name = _nameController.text.trim();
    final defaults = FoodKnowledge.lookup(name);
    if (defaults != null && !_autoFilled) {
      setState(() {
        _selectedCategory = defaults.category;
        _selectedStorage = defaults.storage;
        _suggestedShelfDays = defaults.shelfLifeDays;
        // Auto-select the shelf life if user hasn't chosen one yet
        if (_selectedShelfDays == null && _selectedExpiryDate == null) {
          _applyShelfDays(defaults.shelfLifeDays);
        }
        _autoFilled = true;
      });
      _lookupImage(name);
    } else if (defaults == null) {
      setState(() {
        _autoFilled = false;
        _suggestedShelfDays = null;
      });
    }
  }

  void _applyShelfDays(int days) {
    final date = DateTime.now().add(Duration(days: days));
    setState(() {
      _selectedShelfDays = days;
      _selectedExpiryDate = date;
    });
  }

  double get _computedFreshness {
    if (_selectedExpiryDate == null) return 0.85;
    final now = DateTime.now();
    final total =
        _selectedShelfDays ?? _selectedExpiryDate!.difference(now).inDays.abs();
    if (total <= 0) return 0.0;
    final remaining = _selectedExpiryDate!.difference(now).inDays;
    return (remaining / total).clamp(0.0, 1.0);
  }

  String get _expiryLabel {
    if (_selectedExpiryDate == null) return '新鲜';
    final days = _selectedExpiryDate!.difference(DateTime.now()).inDays;
    if (days < 0) return '已过期${-days}天';
    if (days == 0) return '今天过期';
    if (days == 1) return '明天过期';
    return '$days天后过期';
  }

  void _resetForm() {
    _nameController.clear();
    _quantityController.clear();
    setState(() {
      _selectedCategory = '乳制品与蛋类';
      _selectedStorage = IconType.fridge;
      _selectedUnit = '个';
      _selectedShelfDays = null;
      _selectedExpiryDate = null;
      _suggestedShelfDays = null;
      _autoFilled = false;
      _resolvedImageUrl = '';
    });
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.of(context).push<BarcodeResult>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (result == null || !mounted) return;

    if (result.category != null) {
      _nameController.text = result.productName;
      if (result.imageUrl != null) {
        _resolvedImageUrl = result.imageUrl!;
      }
      setState(() => _selectedCategory = result.category!);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已识别：${result.productName}'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else {
      _nameController.text = result.productName;
      if (result.imageUrl != null) {
        _resolvedImageUrl = result.imageUrl!;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('未找到商品信息，已填入条码号'),
          backgroundColor: AppColors.secondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _save({bool navigateToInventory = false}) {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final quantity = _quantityController.text.trim();
    final freshness = _computedFreshness;

    final ingredient = Ingredient(
      name: name,
      quantity: quantity.isEmpty ? '1' : quantity,
      unit: _selectedUnit,
      imageUrl: _resolvedImageUrl,
      freshnessPercent: freshness,
      state: freshness > 0.5
          ? FreshnessState.fresh
          : freshness > 0.2
          ? FreshnessState.expiringSoon
          : FreshnessState.expired,
      category: _selectedCategory,
      storage: _selectedStorage,
      expiryDate: _selectedExpiryDate,
      expiryLabel: _expiryLabel,
    );

    ref.read(inventoryProvider.notifier).add(ingredient);
    final addedIndex = ref.read(inventoryProvider).length - 1;

    _resetForm();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加「$name」'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: '撤销',
          textColor: AppColors.onPrimary,
          onPressed: () {
            ref.read(inventoryProvider.notifier).remove(addedIndex);
          },
        ),
      ),
    );

    if (navigateToInventory) {
      ref.read(navigationProvider.notifier).state = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final frequentItems = ref.watch(frequentItemsProvider);

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
            '添加新食材到您的收藏。',
            style: GoogleFonts.manrope(
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 24),

          // ── Frequent items ──
          if (frequentItems.isNotEmpty) ...[
            _buildLabel('常购食材'),
            const SizedBox(height: 10),
            _buildFrequentChips(frequentItems),
            const SizedBox(height: 28),
          ],

          // Barcode Scanner
          _buildBarcodeScanner(),

          const SizedBox(height: 28),

          // Ingredient Name
          _buildLabel('食材名称'),
          const SizedBox(height: 8),
          _buildFilledInput(
            controller: _nameController,
            hintText: '例如：牛奶、鸡蛋、番茄...',
            fontSize: 18,
          ),
          if (_autoFilled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  '已智能填充分类、存储位置和保质期',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // Category + Storage (side by side)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('分类'),
                    const SizedBox(height: 8),
                    _buildCategoryDropdown(),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('存储位置'),
                    const SizedBox(height: 8),
                    _buildStorageSelector(),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Quantity + Unit (side by side)
          _buildLabel('数量'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildFilledInput(
                  controller: _quantityController,
                  hintText: '1',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 1, child: _buildUnitDropdown()),
            ],
          ),

          const SizedBox(height: 24),

          // Expiration Section
          _buildExpirationSection(),

          const SizedBox(height: 32),

          // Save Buttons
          _buildSaveButton(),
          const SizedBox(height: 12),
          _buildDiscardButton(),
        ],
      ),
    );
  }

  // ─── Sub-widgets ────────────────────────────────────────────────────

  Widget _buildFrequentChips(List<FrequentItem> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return GestureDetector(
          onTap: () {
            _nameController.text = item.name;
            setState(() {
              _selectedCategory = item.category;
              _selectedStorage = item.storage;
              _selectedUnit = item.unit;
              if (item.shelfLifeDays != null) {
                _applyShelfDays(item.shelfLifeDays!);
              }
              _autoFilled = true;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _storageIcons[item.storage],
                  size: 14,
                  color: AppColors.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  item.name,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBarcodeScanner() {
    return GestureDetector(
      onTap: _scanBarcode,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Icon(
                Icons.qr_code_scanner,
                color: AppColors.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '扫描条码',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  '快速识别商品信息',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: _categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _selectedCategory = v!),
        ),
      ),
    );
  }

  Widget _buildStorageSelector() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<IconType>(
          value: _selectedStorage,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: IconType.values
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(
                        _storageIcons[t],
                        size: 16,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(_storageLabels[t]!),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedStorage = v!),
        ),
      ),
    );
  }

  Widget _buildUnitDropdown() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedUnit,
          isExpanded: true,
          icon: const Icon(
            Icons.expand_more,
            color: AppColors.onSurfaceVariant,
            size: 20,
          ),
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
          dropdownColor: AppColors.surfaceContainerLowest,
          items: FoodKnowledge.units
              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
              .toList(),
          onChanged: (v) => setState(() => _selectedUnit = v!),
        ),
      ),
    );
  }

  Widget _buildExpirationSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLabel('保质期'),
              if (_selectedExpiryDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _computedFreshness > 0.5
                        ? AppColors.primaryContainer
                        : _computedFreshness > 0.2
                        ? AppColors.secondaryContainer
                        : AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _expiryLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _computedFreshness > 0.5
                          ? AppColors.onPrimaryContainer
                          : _computedFreshness > 0.2
                          ? AppColors.onSecondaryContainer
                          : AppColors.onErrorContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Quick-select chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...FoodKnowledge.shelfLifePresets.map(
                (days) => _buildShelfDayChip(days),
              ),
              _buildCustomDateChip(),
            ],
          ),

          if (_selectedExpiryDate != null) ...[
            const SizedBox(height: 16),
            // Show selected date
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedExpiryDate!.year}-'
                    '${_selectedExpiryDate!.month.toString().padLeft(2, '0')}-'
                    '${_selectedExpiryDate!.day.toString().padLeft(2, '0')}',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedShelfDays = null;
                      _selectedExpiryDate = null;
                    }),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GradientFreshnessMeter(percent: _computedFreshness),
          ],
        ],
      ),
    );
  }

  Widget _buildShelfDayChip(int days) {
    final isSelected = _selectedShelfDays == days;
    final isSuggested =
        _suggestedShelfDays != null &&
        FoodKnowledge.shelfLifePresets.contains(_suggestedShelfDays) &&
        _suggestedShelfDays == days;

    return GestureDetector(
      onTap: () => _applyShelfDays(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          border: isSuggested && !isSelected
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
        ),
        child: Text(
          '$days天',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDateChip() {
    final isCustom =
        _selectedExpiryDate != null &&
        !FoodKnowledge.shelfLifePresets.contains(_selectedShelfDays);

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate:
              _selectedExpiryDate ??
              DateTime.now().add(const Duration(days: 7)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 1825)),
        );
        if (picked != null) {
          setState(() {
            _selectedExpiryDate = picked;
            _selectedShelfDays = picked.difference(DateTime.now()).inDays;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isCustom
              ? AppColors.primary
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size: 14,
              color: isCustom ? AppColors.onPrimary : AppColors.onSurface,
            ),
            const SizedBox(width: 4),
            Text(
              '自定义',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isCustom ? AppColors.onPrimary : AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: () => _save(),
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary,
              AppColors.primary.withValues(alpha: 0.8),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_circle, color: AppColors.onPrimary),
            const SizedBox(width: 8),
            Text(
              '保存',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscardButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton(
        onPressed: _resetForm,
        child: Text(
          '丢弃',
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 2)),
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

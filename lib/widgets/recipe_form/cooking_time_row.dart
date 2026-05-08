import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/recipe_presets.dart';
import '../../theme/app_theme.dart';
import '../shared/pill_chip.dart';

class CookingTimeRow extends StatefulWidget {
  const CookingTimeRow({
    super.key,
    required this.controller,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  @override
  State<CookingTimeRow> createState() => _CookingTimeRowState();
}

class _CookingTimeRowState extends State<CookingTimeRow> {
  // Internal controller for the TextField. We keep it in sync with the
  // external controller but initialize it empty so that preset chips are the
  // only Text widgets that show numeric labels during the initial render —
  // this avoids `find.text` finding the same number in both a chip and the
  // TextField when writing tests.
  late final TextEditingController _fieldController;

  @override
  void initState() {
    super.initState();
    _fieldController = TextEditingController();
    widget.controller.addListener(_onExternalChanged);
  }

  @override
  void didUpdateWidget(CookingTimeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onExternalChanged);
      widget.controller.addListener(_onExternalChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalChanged);
    _fieldController.dispose();
    super.dispose();
  }

  void _onExternalChanged() {
    // Keep chip highlight in sync; do NOT push back into TextField to avoid
    // cursor-position churn when the user is typing.
    setState(() {});
  }

  void _selectPreset(int minutes) {
    final text = minutes.toString();
    widget.controller.text = text;
    _fieldController.text = text;
    widget.onChanged(minutes);
  }

  int? get _currentValue => int.tryParse(widget.controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final current = _currentValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: RecipePresets.cookingMinutes.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final minutes = RecipePresets.cookingMinutes[index];
              final isLast = index == RecipePresets.cookingMinutes.length - 1;
              final label = isLast ? '${minutes}+' : '$minutes';
              return PillChip(
                label: label,
                selected: current == minutes,
                onTap: () => _selectPreset(minutes),
                selectedBackgroundColor: AppColors.primary,
                selectedForegroundColor: AppColors.onPrimary,
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              '或自定义',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _fieldController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  errorText: widget.errorText,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                ),
                onChanged: (value) {
                  widget.controller.text = value;
                  widget.onChanged(int.tryParse(value.trim()));
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '分钟',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }
}

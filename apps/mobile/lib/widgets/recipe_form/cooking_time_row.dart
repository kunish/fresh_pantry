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
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(CookingTimeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  void _selectPreset(int minutes) {
    widget.controller.text = minutes.toString();
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
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final minutes = RecipePresets.cookingMinutes[index];
              final isLast = index == RecipePresets.cookingMinutes.length - 1;
              final label = isLast ? '$minutes+' : '$minutes';
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
                controller: widget.controller,
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
                onChanged: (value) =>
                    widget.onChanged(int.tryParse(value.trim())),
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

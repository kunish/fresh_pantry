import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/shopping_provider.dart';
import '../../theme/app_theme.dart';

class QuickAddField extends ConsumerStatefulWidget {
  const QuickAddField({super.key});

  @override
  ConsumerState<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends ConsumerState<QuickAddField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      final added = await ref
          .read(shoppingProvider.notifier)
          .addFromSuggestion(trimmed);
      if (!mounted) return;
      _controller.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      _showAddResult(trimmed, added);
    }
  }

  void _showAddResult(String name, bool added) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? '已添加「$name」' : '「$name」已在购物清单中'),
        persist: false,
        backgroundColor: added ? AppColors.primary : AppColors.tertiary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '添加食材到清单...',
            hintStyle: TextStyle(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            prefixIcon: const Icon(Icons.add_circle, color: AppColors.primary),
            suffixIcon: IconButton(
              icon: const Icon(Icons.send, color: AppColors.primary, size: 20),
              onPressed: () {
                _submit(_controller.text);
              },
            ),
            filled: false,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onSubmitted: (value) {
            _submit(value);
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recipe.dart';
import '../providers/custom_recipe_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../widgets/recipe_card.dart';
import 'custom_recipe_form_screen.dart';
import 'recipe_detail_screen.dart';

class MyRecipesScreen extends ConsumerWidget {
  const MyRecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(customRecipesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的食谱')),
      body:
          recipes.isEmpty
              ? const Center(child: Text('还没有自定义食谱'))
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: recipes.length,
                itemBuilder: (context, index) {
                  return _MyRecipeCard(recipe: recipes[index]);
                },
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const CustomRecipeFormScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('新建食谱'),
      ),
    );
  }
}

class _MyRecipeCard extends ConsumerWidget {
  const _MyRecipeCard({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle =
        recipe.description.isNotEmpty ? recipe.description : recipe.category;
    final inventory = ref.watch(inventoryProvider);
    final matchedCount = matchedIngredientCount(inventory, recipe);

    return RecipeCard(
      recipe: recipe,
      subtitle: subtitle,
      matchedCount: matchedCount,
      onTap: () => _openRecipe(context),
      trailing: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: PopupMenuButton<String>(
          tooltip: '食谱操作',
          onSelected: (value) => _handleMenuSelection(context, ref, value),
          itemBuilder:
              (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
        ),
      ),
    );
  }

  void _openRecipe(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _CustomRecipeDetailRoute(recipeId: recipe.id),
      ),
    );
  }

  Future<void> _handleMenuSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    if (value == 'edit') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CustomRecipeFormScreen(recipe: recipe),
        ),
      );
    }
    if (value == 'delete') {
      final confirmed = await _confirmDeleteRecipe(context, recipe);
      if (!confirmed || !context.mounted) {
        return;
      }

      try {
        await ref.read(customRecipesProvider.notifier).remove(recipe.id);
      } on Object {
        if (context.mounted) {
          _showDeleteFailure(context);
        }
      }
    }
  }
}

class _CustomRecipeDetailRoute extends ConsumerWidget {
  const _CustomRecipeDetailRoute({required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(customRecipesProvider);
    Recipe? latestRecipe;
    for (final recipe in recipes) {
      if (recipe.id == recipeId) {
        latestRecipe = recipe;
        break;
      }
    }

    if (latestRecipe == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('食谱已删除')),
      );
    }

    return RecipeDetailScreen(
      recipe: latestRecipe,
      isCustomRecipe: true,
      onEdit: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CustomRecipeFormScreen(recipe: latestRecipe),
          ),
        );
      },
      onDelete: () async {
        final confirmed = await _confirmDeleteRecipe(context, latestRecipe!);
        if (!confirmed || !context.mounted) {
          return;
        }

        try {
          await ref.read(customRecipesProvider.notifier).remove(recipeId);
        } on Object {
          if (context.mounted) {
            _showDeleteFailure(context);
          }
          return;
        }

        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }
}

Future<bool> _confirmDeleteRecipe(BuildContext context, Recipe recipe) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('删除食谱'),
          content: Text('确定要删除“${recipe.name}”吗？此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
  );

  return confirmed ?? false;
}

void _showDeleteFailure(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('删除失败，请重试'), persist: false));
}

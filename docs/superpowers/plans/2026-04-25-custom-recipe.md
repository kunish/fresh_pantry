# Custom Recipe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build local custom recipe creation, listing, detail viewing, editing, and deletion from a dashboard quick action.

**Architecture:** Reuse the existing `Recipe` model and `RecipeDetailScreen`. Add a focused custom recipe provider backed by `SharedPreferences`, then layer a list screen and a shared add/edit form on top. Custom recipes remain separate from `recommendedRecipesProvider` in this version.

**Tech Stack:** Flutter, Dart, Riverpod `NotifierProvider`, `SharedPreferences`, `flutter_test` widget/provider tests.

---

## File Structure

- Create `lib/providers/custom_recipe_provider.dart`: owns local custom recipe state and persistence.
- Create `lib/screens/my_recipes_screen.dart`: displays saved custom recipes, empty state, add button, edit/delete entry points, and detail navigation.
- Create `lib/screens/custom_recipe_form_screen.dart`: add/edit form for base recipe fields, ingredients, and steps.
- Modify `lib/screens/dashboard_screen.dart`: add the homepage quick action that opens `MyRecipesScreen`.
- Modify `lib/screens/recipe_detail_screen.dart`: add optional custom-recipe management actions without affecting existing recipe detail uses.
- Create `test/custom_recipe_provider_test.dart`: provider persistence and malformed data coverage.
- Create `test/custom_recipe_flow_test.dart`: dashboard entry, empty list, list-to-detail, and form validation coverage.

## Task 1: Custom Recipe Provider

**Files:**
- Create: `lib/providers/custom_recipe_provider.dart`
- Test: `test/custom_recipe_provider_test.dart`

- [ ] **Step 1: Write the failing provider tests**

Create `test/custom_recipe_provider_test.dart` with:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('customRecipesProvider', () {
    test('loads an empty list when no custom recipes are saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(customRecipesProvider), isEmpty);
    });

    test('adds a recipe and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(customRecipesProvider.notifier).add(_recipe('r1'));

      expect(container.read(customRecipesProvider).single.name, '番茄炒蛋');
      final saved = json.decode(prefs.getString('custom_recipes')!);
      expect(saved, isA<List<dynamic>>());
      expect(saved.single['id'], 'r1');
    });

    test('updates a recipe while preserving its id', () async {
      SharedPreferences.setMockInitialValues({
        'custom_recipes': json.encode([_recipe('r1').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(customRecipesProvider.notifier).update(
            'r1',
            _recipe('different').copyWith(name: '黑椒鸡胸'),
          );

      final updated = container.read(customRecipesProvider).single;
      expect(updated.id, 'r1');
      expect(updated.name, '黑椒鸡胸');
    });

    test('removes a recipe and persists removal', () async {
      SharedPreferences.setMockInitialValues({
        'custom_recipes': json.encode([_recipe('r1').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(customRecipesProvider.notifier).remove('r1');

      expect(container.read(customRecipesProvider), isEmpty);
      expect(json.decode(prefs.getString('custom_recipes')!), isEmpty);
    });

    test('malformed saved JSON falls back to an empty list', () async {
      SharedPreferences.setMockInitialValues({'custom_recipes': '{bad json'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(customRecipesProvider), isEmpty);
    });
  });
}

Recipe _recipe(String id) {
  return Recipe(
    id: id,
    name: '番茄炒蛋',
    category: '家常',
    difficulty: 1,
    cookingMinutes: 15,
    description: '快手家常菜',
    ingredients: const [
      RecipeIngredient(name: '番茄', amount: '2个'),
      RecipeIngredient(name: '鸡蛋', amount: '2个'),
    ],
    steps: const ['切番茄', '炒鸡蛋', '合炒调味'],
  );
}
```

- [ ] **Step 2: Run the provider tests and verify RED**

Run: `flutter test test/custom_recipe_provider_test.dart`

Expected: FAIL because `custom_recipe_provider.dart` and `customRecipesProvider` do not exist.

- [ ] **Step 3: Implement the provider**

Create `lib/providers/custom_recipe_provider.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe.dart';
import 'storage_service_provider.dart';

const customRecipesStorageKey = 'custom_recipes';

class CustomRecipeNotifier extends Notifier<List<Recipe>> {
  late final SharedPreferences _prefs;

  @override
  List<Recipe> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _load();
  }

  List<Recipe> _load() {
    final jsonString = _prefs.getString(customRecipesStorageKey);
    if (jsonString == null) return [];

    try {
      final raw = json.decode(jsonString);
      if (raw is! List<dynamic>) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Recipe.fromJson)
          .where((recipe) => recipe.id.isNotEmpty && recipe.name.isNotEmpty)
          .toList();
    } catch (error) {
      if (kDebugMode) {
        print('Error decoding custom recipes: $error');
      }
      return [];
    }
  }

  Future<void> _save(List<Recipe> recipes) async {
    await _prefs.setString(
      customRecipesStorageKey,
      json.encode(recipes.map((recipe) => recipe.toJson()).toList()),
    );
  }

  Future<void> add(Recipe recipe) async {
    final updated = [...state, recipe];
    state = updated;
    await _save(updated);
  }

  Future<void> update(String id, Recipe recipe) async {
    final index = state.indexWhere((item) => item.id == id);
    if (index == -1) return;

    final updated = [...state];
    updated[index] = recipe.copyWith(id: id);
    state = updated;
    await _save(updated);
  }

  Future<void> remove(String id) async {
    final updated = state.where((recipe) => recipe.id != id).toList();
    if (updated.length == state.length) return;

    state = updated;
    await _save(updated);
  }
}

final customRecipesProvider =
    NotifierProvider<CustomRecipeNotifier, List<Recipe>>(
  CustomRecipeNotifier.new,
);
```

- [ ] **Step 4: Run provider tests and format**

Run: `dart format lib/providers/custom_recipe_provider.dart test/custom_recipe_provider_test.dart`

Run: `flutter test test/custom_recipe_provider_test.dart`

Expected: PASS, all provider tests green.

- [ ] **Step 5: Checkpoint**

Run: `git diff -- lib/providers/custom_recipe_provider.dart test/custom_recipe_provider_test.dart`

Expected: diff contains only the provider and provider tests. Do not commit unless the user explicitly asks for a commit.

## Task 2: My Recipes List And Dashboard Entry

**Files:**
- Create: `lib/screens/my_recipes_screen.dart`
- Modify: `lib/screens/dashboard_screen.dart`
- Test: `test/custom_recipe_flow_test.dart`

- [ ] **Step 1: Write failing widget tests for entry and list**

Create `test/custom_recipe_flow_test.dart` with:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/dashboard_screen.dart';
import 'package:fresh_pantry/screens/my_recipes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dashboard quick action opens my recipes screen', (tester) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const DashboardScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加食谱'));
    await tester.pumpAndSettle();

    expect(find.text('我的食谱'), findsOneWidget);
    expect(find.text('还没有自定义食谱'), findsOneWidget);
  });

  testWidgets('my recipes screen shows saved recipes', (tester) async {
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('番茄炒蛋'), findsOneWidget);
    expect(find.text('快手家常菜'), findsOneWidget);
  });
}

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Widget _app(SharedPreferences prefs, Widget child) {
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Recipe _recipe(String id) {
  return Recipe(
    id: id,
    name: '番茄炒蛋',
    category: '家常',
    difficulty: 1,
    cookingMinutes: 15,
    description: '快手家常菜',
    ingredients: const [RecipeIngredient(name: '番茄', amount: '2个')],
    steps: const ['切番茄', '炒熟'],
  );
}
```

- [ ] **Step 2: Run widget tests and verify RED**

Run: `flutter test test/custom_recipe_flow_test.dart`

Expected: FAIL because `my_recipes_screen.dart` and dashboard quick action do not exist.

- [ ] **Step 3: Create `MyRecipesScreen`**

Create `lib/screens/my_recipes_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/recipe.dart';
import '../providers/custom_recipe_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../theme/app_theme.dart';
import 'custom_recipe_form_screen.dart';
import 'recipe_detail_screen.dart';

class MyRecipesScreen extends ConsumerWidget {
  const MyRecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(customRecipesProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '我的食谱',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('新建食谱'),
      ),
      body: recipes.isEmpty
          ? const _EmptyRecipesState()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
              itemCount: recipes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final recipe = recipes[index];
                return _CustomRecipeCard(
                  recipe: recipe,
                  matchedCount: matchedIngredientCount(
                    ref.watch(inventoryProvider),
                    recipe,
                  ),
                  onTap: () => _openDetail(context, ref, recipe),
                  onEdit: () => _openForm(context, recipe: recipe),
                  onDelete: () => _confirmDelete(context, ref, recipe),
                );
              },
            ),
    );
  }

  void _openForm(BuildContext context, {Recipe? recipe}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomRecipeFormScreen(recipe: recipe),
      ),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref, Recipe recipe) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          recipe: recipe,
          isCustomRecipe: true,
          onEdit: () => _openForm(context, recipe: recipe),
          onDelete: () => _confirmDelete(context, ref, recipe),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Recipe recipe) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除食谱'),
        content: Text('确定要删除「${recipe.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(customRecipesProvider.notifier).remove(recipe.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecipesState extends StatelessWidget {
  const _EmptyRecipesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 64, color: AppColors.outline),
            const SizedBox(height: 16),
            Text(
              '还没有自定义食谱',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '保存常做菜、家人偏好和厨房灵感。',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomRecipeCard extends StatelessWidget {
  final Recipe recipe;
  final int matchedCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomRecipeCard({
    required this.recipe,
    required this.matchedCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: recipe.name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipe.description.isEmpty ? recipe.category : recipe.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${recipe.cookingMinutes}分钟 · 难度 ${recipe.difficulty} · $matchedCount/${recipe.ingredients.length} 已备',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add dashboard quick action**

Modify `lib/screens/dashboard_screen.dart` imports:

```dart
import 'my_recipes_screen.dart';
```

Replace the current two-card quick action `IntrinsicHeight` block with a `Column` containing the existing row plus a full-width custom recipe card:

```dart
Column(
  children: [
    IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: QuickActionCard(
              icon: Icons.add_circle,
              title: '添加新食材',
              subtitle: '扫码或手动录入',
              backgroundColor: AppColors.primary,
              contentColor: AppColors.onPrimary,
              onTap: () {
                ref.read(navigationProvider.notifier).state = 2;
              },
              semanticLabel: '添加新食材，扫码或手动录入',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: QuickActionCard(
              icon: Icons.shopping_basket,
              title: '购物清单',
              subtitle: '还需$uncheckedCount件',
              backgroundColor: AppColors.tertiaryFixedDim,
              contentColor: AppColors.onTertiaryFixedDim,
              onTap: () {
                ref.read(navigationProvider.notifier).state = 3;
              },
              semanticLabel: '购物清单，还需$uncheckedCount件',
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    QuickActionCard(
      icon: Icons.menu_book_outlined,
      title: '添加食谱',
      subtitle: '管理我的私房菜单',
      backgroundColor: AppColors.surfaceContainerHigh,
      contentColor: AppColors.onSurface,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MyRecipesScreen()),
        );
      },
      semanticLabel: '添加食谱，管理我的私房菜单',
    ),
  ],
)
```

- [ ] **Step 5: Run tests and format**

Run: `dart format lib/screens/my_recipes_screen.dart lib/screens/dashboard_screen.dart test/custom_recipe_flow_test.dart`

Run: `flutter test test/custom_recipe_flow_test.dart`

Expected: tests still fail only because `CustomRecipeFormScreen` does not exist. If Dart compilation fails for that missing file, create the minimal shell from Task 3 Step 3 before continuing.

- [ ] **Step 6: Checkpoint**

Run: `git diff -- lib/screens/my_recipes_screen.dart lib/screens/dashboard_screen.dart test/custom_recipe_flow_test.dart`

Expected: diff contains the new list screen, dashboard entry, and widget tests. Do not commit unless the user explicitly asks for a commit.

## Task 3: Custom Recipe Add Form And Validation

**Files:**
- Create: `lib/screens/custom_recipe_form_screen.dart`
- Modify: `test/custom_recipe_flow_test.dart`

- [ ] **Step 1: Add failing form validation test**

Append this test to `test/custom_recipe_flow_test.dart`:

```dart
testWidgets('custom recipe form blocks save when required fields are missing', (tester) async {
  final prefs = await _prefs({});

  await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
  await tester.pumpAndSettle();

  await tester.tap(find.text('保存食谱'));
  await tester.pumpAndSettle();

  expect(find.text('请填写食谱名称'), findsOneWidget);
});
```

Add the missing import:

```dart
import 'package:fresh_pantry/screens/custom_recipe_form_screen.dart';
```

- [ ] **Step 2: Run form test and verify RED**

Run: `flutter test test/custom_recipe_flow_test.dart --plain-name "custom recipe form blocks save when required fields are missing"`

Expected: FAIL because the form screen does not exist or does not validate.

- [ ] **Step 3: Create add/edit form screen**

Create `lib/screens/custom_recipe_form_screen.dart` with these responsibilities:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/recipe.dart';
import '../providers/custom_recipe_provider.dart';
import '../theme/app_theme.dart';

class CustomRecipeFormScreen extends ConsumerStatefulWidget {
  final Recipe? recipe;

  const CustomRecipeFormScreen({super.key, this.recipe});

  @override
  ConsumerState<CustomRecipeFormScreen> createState() => _CustomRecipeFormScreenState();
}

class _CustomRecipeFormScreenState extends ConsumerState<CustomRecipeFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _minutesController;
  late final TextEditingController _difficultyController;
  late final TextEditingController _descriptionController;
  late final List<_IngredientControllers> _ingredients;
  late final List<TextEditingController> _steps;

  bool get _isEditing => widget.recipe != null;

  @override
  void initState() {
    super.initState();
    final recipe = widget.recipe;
    _nameController = TextEditingController(text: recipe?.name ?? '');
    _categoryController = TextEditingController(text: recipe?.category ?? '家常');
    _minutesController = TextEditingController(text: recipe?.cookingMinutes.toString() ?? '');
    _difficultyController = TextEditingController(text: recipe?.difficulty.toString() ?? '1');
    _descriptionController = TextEditingController(text: recipe?.description ?? '');
    _ingredients = recipe?.ingredients
            .map((item) => _IngredientControllers(name: item.name, amount: item.amount))
            .toList() ??
        [_IngredientControllers()];
    _steps = recipe?.steps.map(TextEditingController.new).toList() ?? [TextEditingController()];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _minutesController.dispose();
    _difficultyController.dispose();
    _descriptionController.dispose();
    for (final ingredient in _ingredients) {
      ingredient.dispose();
    }
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  String? _validationError() {
    if (_nameController.text.trim().isEmpty) return '请填写食谱名称';
    if (_categoryController.text.trim().isEmpty) return '请填写分类';
    final minutes = int.tryParse(_minutesController.text.trim());
    if (minutes == null || minutes <= 0) return '请填写有效烹饪时间';
    final difficulty = int.tryParse(_difficultyController.text.trim());
    if (difficulty == null || difficulty < 1 || difficulty > 5) return '难度需为 1-5';
    final validIngredients = _ingredients.where((item) => item.name.text.trim().isNotEmpty && item.amount.text.trim().isNotEmpty);
    if (validIngredients.isEmpty) return '请至少添加一种食材';
    final validSteps = _steps.where((step) => step.text.trim().isNotEmpty);
    if (validSteps.isEmpty) return '请至少添加一个步骤';
    return null;
  }

  Future<void> _save() async {
    final error = _validationError();
    if (error != null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final recipe = Recipe(
      id: widget.recipe?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      category: _categoryController.text.trim(),
      difficulty: int.parse(_difficultyController.text.trim()),
      cookingMinutes: int.parse(_minutesController.text.trim()),
      description: _descriptionController.text.trim(),
      ingredients: _ingredients
          .where((item) => item.name.text.trim().isNotEmpty && item.amount.text.trim().isNotEmpty)
          .map((item) => RecipeIngredient(name: item.name.text.trim(), amount: item.amount.text.trim()))
          .toList(),
      steps: _steps.map((step) => step.text.trim()).where((step) => step.isNotEmpty).toList(),
    );

    final notifier = ref.read(customRecipesProvider.notifier);
    if (_isEditing) {
      await notifier.update(widget.recipe!.id, recipe);
    } else {
      await notifier.add(recipe);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _IngredientControllers {
  final TextEditingController name;
  final TextEditingController amount;

  _IngredientControllers({String name = '', String amount = ''})
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount);

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}
```

Add the `build` method inside `_CustomRecipeFormScreenState`:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.surface,
    appBar: AppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        _isEditing ? '编辑食谱' : '新建食谱',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      children: [
        _field(_nameController, '食谱名称 *'),
        _field(_categoryController, '分类 *'),
        _field(_minutesController, '烹饪时间（分钟）*', keyboardType: TextInputType.number),
        _field(_difficultyController, '难度 1-5 *', keyboardType: TextInputType.number),
        _field(_descriptionController, '简介', maxLines: 3),
        _sectionTitle('所需食材'),
        ..._ingredients.asMap().entries.map((entry) {
          return Row(
            children: [
              Expanded(child: _field(entry.value.name, '食材名称')),
              const SizedBox(width: 8),
              Expanded(child: _field(entry.value.amount, '用量')),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _ingredients.length == 1
                    ? null
                    : () => setState(() {
                          final removed = _ingredients.removeAt(entry.key);
                          removed.dispose();
                        }),
              ),
            ],
          );
        }),
        TextButton.icon(
          onPressed: () => setState(() => _ingredients.add(_IngredientControllers())),
          icon: const Icon(Icons.add),
          label: const Text('添加食材'),
        ),
        _sectionTitle('烹饪步骤'),
        ..._steps.asMap().entries.map((entry) {
          return Row(
            children: [
              Expanded(child: _field(entry.value, '步骤 ${entry.key + 1}', maxLines: 2)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _steps.length == 1
                    ? null
                    : () => setState(() {
                          final removed = _steps.removeAt(entry.key);
                          removed.dispose();
                        }),
              ),
            ],
          );
        }),
        TextButton.icon(
          onPressed: () => setState(() => _steps.add(TextEditingController())),
          icon: const Icon(Icons.add),
          label: const Text('添加步骤'),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: FilledButton(
          onPressed: _save,
          child: const Text('保存食谱'),
        ),
      ),
    ),
  );
}

Widget _field(
  TextEditingController controller,
  String label, {
  TextInputType? keyboardType,
  int maxLines = 1,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}

Widget _sectionTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(
      text,
      style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700),
    ),
  );
}
```

- [ ] **Step 4: Run form tests and format**

Run: `dart format lib/screens/custom_recipe_form_screen.dart test/custom_recipe_flow_test.dart`

Run: `flutter test test/custom_recipe_flow_test.dart --plain-name "custom recipe form blocks save when required fields are missing"`

Expected: PASS.

- [ ] **Step 5: Checkpoint**

Run: `git diff -- lib/screens/custom_recipe_form_screen.dart test/custom_recipe_flow_test.dart`

Expected: diff contains the form screen and validation test. Do not commit unless the user explicitly asks for a commit.

## Task 4: Detail Management, Edit, And Delete Flow

**Files:**
- Modify: `lib/screens/recipe_detail_screen.dart`
- Modify: `lib/screens/my_recipes_screen.dart`
- Modify: `test/custom_recipe_flow_test.dart`

- [ ] **Step 1: Add failing list-to-detail and delete tests**

Append these tests to `test/custom_recipe_flow_test.dart`:

```dart
testWidgets('saved custom recipe opens detail screen', (tester) async {
  final prefs = await _prefs({
    customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
  });

  await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
  await tester.pumpAndSettle();

  await tester.tap(find.text('番茄炒蛋'));
  await tester.pumpAndSettle();

  expect(find.text('所需食材'), findsOneWidget);
  expect(find.text('烹饪步骤'), findsOneWidget);
});

testWidgets('custom recipe can be deleted from the list menu', (tester) async {
  final prefs = await _prefs({
    customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
  });

  await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('删除').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('删除').last);
  await tester.pumpAndSettle();

  expect(find.text('番茄炒蛋'), findsNothing);
  expect(find.text('还没有自定义食谱'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/custom_recipe_flow_test.dart --plain-name "saved custom recipe opens detail screen"`

Expected: FAIL if detail navigation or custom management hooks are incomplete.

Run: `flutter test test/custom_recipe_flow_test.dart --plain-name "custom recipe can be deleted from the list menu"`

Expected: FAIL if menu delete flow is incomplete.

- [ ] **Step 3: Add optional management actions to `RecipeDetailScreen`**

Modify the widget constructor in `lib/screens/recipe_detail_screen.dart`:

```dart
class RecipeDetailScreen extends ConsumerStatefulWidget {
  final Recipe recipe;
  final bool isCustomRecipe;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    this.isCustomRecipe = false,
    this.onEdit,
    this.onDelete,
  });
```

Add `actions` to the existing `SliverAppBar`:

```dart
actions: [
  if (widget.isCustomRecipe && widget.onEdit != null)
    IconButton(
      tooltip: '编辑食谱',
      icon: const Icon(Icons.edit_outlined),
      onPressed: widget.onEdit,
    ),
  if (widget.isCustomRecipe && widget.onDelete != null)
    IconButton(
      tooltip: '删除食谱',
      icon: const Icon(Icons.delete_outline),
      onPressed: widget.onDelete,
    ),
],
```

- [ ] **Step 4: Ensure list callbacks keep navigation coherent**

In `lib/screens/my_recipes_screen.dart`, update `_openDetail` delete callback so deleting from detail removes the recipe and closes detail:

```dart
void _openDetail(BuildContext context, WidgetRef ref, Recipe recipe) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (detailContext) => RecipeDetailScreen(
        recipe: recipe,
        isCustomRecipe: true,
        onEdit: () => _openForm(detailContext, recipe: recipe),
        onDelete: () {
          _confirmDelete(detailContext, ref, recipe, popAfterDelete: true);
        },
      ),
    ),
  );
}
```

Update `_confirmDelete` signature and delete action:

```dart
void _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Recipe recipe, {
  bool popAfterDelete = false,
}) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除食谱'),
      content: Text('确定要删除「${recipe.name}」吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            ref.read(customRecipesProvider.notifier).remove(recipe.id);
            if (popAfterDelete) {
              Navigator.pop(context);
            }
          },
          child: const Text('删除'),
        ),
      ],
    ),
  );
}
```

Update list card delete caller:

```dart
onDelete: () => _confirmDelete(context, ref, recipe),
```

- [ ] **Step 5: Run flow tests and format**

Run: `dart format lib/screens/recipe_detail_screen.dart lib/screens/my_recipes_screen.dart test/custom_recipe_flow_test.dart`

Run: `flutter test test/custom_recipe_flow_test.dart`

Expected: PASS, all custom recipe flow tests green.

- [ ] **Step 6: Checkpoint**

Run: `git diff -- lib/screens/recipe_detail_screen.dart lib/screens/my_recipes_screen.dart test/custom_recipe_flow_test.dart`

Expected: diff contains optional detail actions and delete flow. Do not commit unless the user explicitly asks for a commit.

## Task 5: Integration Verification And Polish

**Files:**
- Modify only files touched by Tasks 1-4 if verification reveals a defect.

- [ ] **Step 1: Run targeted tests**

Run: `flutter test test/custom_recipe_provider_test.dart test/custom_recipe_flow_test.dart`

Expected: PASS, all custom recipe tests green.

- [ ] **Step 2: Run full static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Run full test suite**

Run: `flutter test`

Expected: `All tests passed!`

- [ ] **Step 4: Review changed files**

Run: `git diff -- lib/providers/custom_recipe_provider.dart lib/screens/my_recipes_screen.dart lib/screens/custom_recipe_form_screen.dart lib/screens/dashboard_screen.dart lib/screens/recipe_detail_screen.dart test/custom_recipe_provider_test.dart test/custom_recipe_flow_test.dart`

Expected: changes match the approved spec: dashboard entry, local provider persistence, my recipes list, add/edit form, detail management actions, and tests.

- [ ] **Step 5: Final checkpoint**

Run: `git status --short`

Expected: the custom recipe files are modified or untracked alongside any pre-existing unrelated workspace changes. Do not revert unrelated changes. Do not commit unless the user explicitly asks for a commit.

## Self-Review

Spec coverage:

- Dashboard quick-action entry: Task 2.
- Create/view/edit/delete custom recipes: Tasks 2, 3, and 4.
- SharedPreferences persistence: Task 1.
- Reuse existing `Recipe` model and detail screen: Tasks 1 and 4.
- Keep custom recipes separate from recommendations: Task 1 creates a separate provider; no task modifies `recommendedRecipesProvider`.
- Basic fields and validation: Task 3.
- Provider and widget tests: Tasks 1-5.

Placeholder scan:

- No placeholder sections are left in this plan.
- Each code-changing task includes concrete file paths, code, commands, and expected results.

Type consistency:

- Provider name is consistently `customRecipesProvider`.
- Storage key is consistently `custom_recipes` through `customRecipesStorageKey`.
- Screens are consistently `MyRecipesScreen` and `CustomRecipeFormScreen`.
- Detail hooks are consistently `isCustomRecipe`, `onEdit`, and `onDelete`.

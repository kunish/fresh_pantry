# 探索 tab 换用 HowToCook 本地中文食谱库 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把探索 tab 的食谱数据源从 TheMealDB（远程/英文/西餐）换成 HowToCook（本地/中文/家常菜），保住「按库存食材推荐」核心交互。

**Architecture:** 离线预处理脚本把 HowToCook 的 markdown 解析成 `assets/recipes/howtocook.json`；app 运行时由 `LocalRecipeRepository` 读取该 asset，`recipesFetchProvider` 改为加载全部本地食谱（不再联网、不再英文翻译）。探索 tab 展示全集 + 既有的本地搜索/时间筛选；按食材匹配排序仍由 `recommendedRecipesProvider` 承担，对数据来源透明。TheMealDB 调用链整体删除。

**Tech Stack:** Dart / Flutter, flutter_riverpod, flutter_test。无新增依赖（markdown 用纯字符串解析）。

**Spec:** `docs/superpowers/specs/2026-06-02-explore-recipes-howtocook-design.md`

---

## File Structure

新增：
- `apps/mobile/tool/howtocook_parser.dart` — 纯 Dart 解析器：单篇 markdown → `Recipe?`。不依赖 Flutter。
- `apps/mobile/tool/import_howtocook.dart` — CLI：递归扫 `dishes/**/*.md` → 写 `assets/recipes/howtocook.json`。
- `apps/mobile/assets/recipes/howtocook.json` — 解析产物（提交进仓库）。
- `apps/mobile/lib/storage/local_recipe_repository.dart` — 读 asset json → `List<Recipe>`，缓存解析结果。
- `apps/mobile/test/howtocook_parser_test.dart` — 解析器单测。
- `apps/mobile/test/local_recipe_repository_test.dart` — repository 单测。
- `apps/mobile/test/fixtures/howtocook/可乐鸡翅.md`、`冷吃兔.md` — 解析 fixture（curl 下载）。

修改：
- `apps/mobile/lib/providers/recipe_provider.dart` — 加 `localRecipeRepositoryProvider`；`recipesFetchProvider` 改为加载本地全集；删 `mealDbApiProvider` / `recipeSearchRepositoryProvider` / TheMealDB & recipe_search_repo 的 import/export / `FoodKnowledge.englishName` 调用。
- `apps/mobile/pubspec.yaml` — `flutter.assets` 加 `- assets/recipes/`。
- `apps/mobile/test/provider_logic_test.dart` — 改写 `recipesProvider cache` group。
- `apps/mobile/lib/screens/settings_screen.dart` — 「更多」section 加「开源致谢」行。
- 引用 `mealDbApiProvider` / `recipeSearchRepositoryProvider` 的其它测试（见 Task 5 grep）。

删除：
- `apps/mobile/lib/services/themealdb_service.dart`
- `apps/mobile/lib/storage/recipe_search_repo.dart`
- `apps/mobile/test/themealdb_service_test.dart`

> 所有命令默认在 `apps/mobile/` 下执行。只对本次改动涉及的文件运行 `dart format`（仓库约定，避免无关重排）。

---

## Task 1: HowToCook markdown 解析器

**Files:**
- Create: `apps/mobile/tool/howtocook_parser.dart`
- Create: `apps/mobile/test/howtocook_parser_test.dart`
- Create (download): `apps/mobile/test/fixtures/howtocook/可乐鸡翅.md`, `apps/mobile/test/fixtures/howtocook/冷吃兔.md`

- [ ] **Step 1: 下载两个 fixture**

```bash
mkdir -p test/fixtures/howtocook
curl -fsSL "https://raw.githubusercontent.com/Anduin2017/HowToCook/master/dishes/meat_dish/可乐鸡翅.md" -o "test/fixtures/howtocook/可乐鸡翅.md"
curl -fsSL "https://raw.githubusercontent.com/Anduin2017/HowToCook/master/dishes/meat_dish/冷吃兔.md" -o "test/fixtures/howtocook/冷吃兔.md"
```

Expected: 两个文件存在且非空（`可乐鸡翅.md` 含 `预估烹饪难度：★★★`，`冷吃兔.md` 含 `预估烹饪难度：★★★★` 且用 `-` bullet）。

- [ ] **Step 2: 写失败测试**

```dart
// apps/mobile/test/howtocook_parser_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// 相对 import：解析器是 build-time 工具，不进 app 包
import '../tool/howtocook_parser.dart';

void main() {
  String fixture(String name) =>
      File('test/fixtures/howtocook/$name').readAsStringSync();

  group('parseHowToCookMarkdown', () {
    test('解析「可乐鸡翅」（* bullet、计算段含分量）', () {
      final recipe = parseHowToCookMarkdown(
        fixture('可乐鸡翅.md'),
        relativePath: 'meat_dish/可乐鸡翅.md',
      );

      expect(recipe, isNotNull);
      expect(recipe!.id, 'howtocook:meat_dish/可乐鸡翅');
      expect(recipe.name, '可乐鸡翅');
      expect(recipe.category, '荤菜');
      expect(recipe.difficulty, 3);
      expect(recipe.cookingMinutes, 40); // 难度 3 → 40
      expect(recipe.description, contains('可乐鸡翅'));
      // 食材取自「## 必备原料和工具」段（8 项），全部只有 name、amount 为空
      expect(recipe.ingredients.map((i) => i.name), contains('鸡翅中'));
      expect(recipe.ingredients.map((i) => i.name), contains('可乐'));
      expect(recipe.ingredients.length, 8);
      expect(recipe.ingredients.every((i) => i.amount.isEmpty), isTrue);
      // 步骤取自「## 操作」段的顶层有序项（7 条），缩进子贴士被忽略
      expect(recipe.steps.length, 7);
      expect(recipe.steps.first, contains('鸡翅入锅'));
    });

    test('解析「冷吃兔」（- bullet、计算段是公式）', () {
      final recipe = parseHowToCookMarkdown(
        fixture('冷吃兔.md'),
        relativePath: 'meat_dish/冷吃兔.md',
      );

      expect(recipe, isNotNull);
      expect(recipe!.name, '冷吃兔');
      expect(recipe.difficulty, 4);
      expect(recipe.cookingMinutes, 60); // 难度 4 → 60
      // - bullet 也能解析；食材名来自必备原料段，不受「计算」段公式干扰
      expect(recipe.ingredients.map((i) => i.name), contains('兔肉'));
      expect(recipe.ingredients.length, 17);
      expect(recipe.steps.length, 10);
    });

    test('无 # 标题 → null', () {
      expect(
        parseHowToCookMarkdown('没有标题\n\n## 操作\n\n1. 做菜',
            relativePath: 'meat_dish/x.md'),
        isNull,
      );
    });

    test('无「## 操作」段 → null（非菜谱，如 README）', () {
      expect(
        parseHowToCookMarkdown('# 介绍\n\n一些说明文字',
            relativePath: 'meat_dish/README.md'),
        isNull,
      );
    });

    test('未知目录 → 类别「其他」', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试菜的做法\n\n## 必备原料和工具\n\n- 盐\n\n## 操作\n\n1. 做',
        relativePath: 'unknown_dir/测试菜.md',
      );
      expect(recipe!.category, '其他');
    });
  });
}
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `flutter test test/howtocook_parser_test.dart`
Expected: FAIL —— `Error: Couldn't resolve the package ... tool/howtocook_parser.dart` 或 `parseHowToCookMarkdown` 未定义。

- [ ] **Step 4: 实现解析器**

```dart
// apps/mobile/tool/howtocook_parser.dart
import 'package:fresh_pantry/models/recipe.dart';

/// HowToCook `dishes/<dir>/` 目录名 → 中文类别。
const Map<String, String> howtocookCategoryByDir = {
  'aquatic': '水产',
  'breakfast': '早餐',
  'condiment': '酱料',
  'dessert': '甜品',
  'drink': '饮品',
  'meat_dish': '荤菜',
  'semi-finished': '半成品',
  'soup': '汤羹',
  'staple': '主食',
  'vegetable_dish': '素菜',
};

const Map<int, int> _minutesByDifficulty = {1: 15, 2: 25, 3: 40, 4: 60, 5: 90};
const int _defaultMinutes = 30;

final RegExp _bullet = RegExp(r'^\s*[*-]\s+(.*)$');
final RegExp _ordered = RegExp(r'^\s*\d+\.\s+(.*)$');

/// 解析单篇 HowToCook 菜谱 markdown 为 [Recipe]。
/// [relativePath] 是相对 `dishes/` 的路径，例如 `meat_dish/可乐鸡翅.md`。
/// 当文档不是菜谱（无 `# ` 标题、或无 `## 操作` 段）时返回 null。
Recipe? parseHowToCookMarkdown(
  String markdown, {
  required String relativePath,
}) {
  final lines = markdown.split('\n');

  final title = _firstTitle(lines);
  if (title == null) return null;
  final name = title.endsWith('的做法')
      ? title.substring(0, title.length - 3)
      : title;

  final sections = _splitSections(lines);
  final operation = sections['操作'];
  if (operation == null) return null; // 非菜谱

  final difficulty = _parseDifficulty(lines);
  final ingredients = _parseIngredients(sections['必备原料和工具'] ?? const []);
  final steps = _parseSteps(operation);
  final description = _parseDescription(lines);
  final category =
      howtocookCategoryByDir[_firstSegment(relativePath)] ?? '其他';
  final cookingMinutes = _minutesByDifficulty[difficulty] ?? _defaultMinutes;
  final id = 'howtocook:${relativePath.replaceAll(RegExp(r'\.md$'), '')}';

  return Recipe(
    id: id,
    name: name,
    category: category,
    difficulty: difficulty,
    cookingMinutes: cookingMinutes,
    description: description,
    ingredients: ingredients,
    steps: steps,
    tags: [category],
  );
}

String? _firstTitle(List<String> lines) {
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('# ')) return t.substring(2).trim();
  }
  return null;
}

String _firstSegment(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/');
  final idx = normalized.indexOf('/');
  return idx == -1 ? '' : normalized.substring(0, idx);
}

/// 切成 `## ` 段：标题（去掉 `## `）→ 段内行。
Map<String, List<String>> _splitSections(List<String> lines) {
  final sections = <String, List<String>>{};
  String? current;
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('## ')) {
      current = t.substring(3).trim();
      sections[current] = <String>[];
    } else if (current != null) {
      sections[current]!.add(line);
    }
  }
  return sections;
}

int _parseDifficulty(List<String> lines) {
  for (final line in lines) {
    if (line.contains('预估烹饪难度')) {
      return '★'.allMatches(line).length.clamp(0, 5);
    }
  }
  return 0;
}

/// 食材名来自「必备原料和工具」段（纯食材名，统一、可靠）。amount 留空。
List<RecipeIngredient> _parseIngredients(List<String> body) {
  final result = <RecipeIngredient>[];
  for (final line in body) {
    final m = _bullet.firstMatch(line);
    if (m == null) continue;
    final name = m.group(1)!.trim();
    if (name.isEmpty) continue;
    result.add(RecipeIngredient(name: name));
  }
  return result;
}

/// 仅取顶层有序项（`1. `…）作为步骤；缩进的子贴士忽略。
List<String> _parseSteps(List<String> body) {
  final result = <String>[];
  for (final line in body) {
    if (line.startsWith(' ') || line.startsWith('\t')) continue;
    final m = _ordered.firstMatch(line);
    if (m == null) continue;
    final step = m.group(1)!.trim();
    if (step.isNotEmpty) result.add(step);
  }
  return result;
}

/// 标题之后、`预估`/`## ` 之前的第一段非空文本。
String _parseDescription(List<String> lines) {
  final buffer = <String>[];
  var seenTitle = false;
  for (final line in lines) {
    final t = line.trim();
    if (!seenTitle) {
      if (t.startsWith('# ')) seenTitle = true;
      continue;
    }
    if (t.isEmpty) {
      if (buffer.isNotEmpty) break;
      continue;
    }
    if (t.startsWith('预估') || t.startsWith('#')) break;
    buffer.add(t);
  }
  return buffer.join(' ');
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `flutter test test/howtocook_parser_test.dart`
Expected: PASS（5 个测试全绿）。

- [ ] **Step 6: 格式化 + 提交**

```bash
dart format tool/howtocook_parser.dart test/howtocook_parser_test.dart
git add tool/howtocook_parser.dart test/howtocook_parser_test.dart "test/fixtures/howtocook/可乐鸡翅.md" "test/fixtures/howtocook/冷吃兔.md"
git commit -m "feat(recipes): HowToCook markdown 解析器 + 测试"
```

---

## Task 2: 导入脚本 + 生成 asset + 注册 pubspec

**Files:**
- Create: `apps/mobile/tool/import_howtocook.dart`
- Create: `apps/mobile/assets/recipes/howtocook.json`（脚本产物）
- Modify: `apps/mobile/pubspec.yaml:97-99`

- [ ] **Step 1: 实现导入脚本**

```dart
// apps/mobile/tool/import_howtocook.dart
//
// 用法: dart run tool/import_howtocook.dart <HowToCook clone 路径> [输出路径]
// 数据来源: https://github.com/Anduin2017/HowToCook (Unlicense)
//
// 先 clone 一份上游:
//   git clone --depth 1 https://github.com/Anduin2017/HowToCook /tmp/HowToCook
import 'dart:convert';
import 'dart:io';

import 'howtocook_parser.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/import_howtocook.dart <HowToCook-clone-path> [out.json]',
    );
    exit(64);
  }
  final repoRoot = args[0];
  final outPath = args.length > 1 ? args[1] : 'assets/recipes/howtocook.json';

  final dishesDir = Directory('$repoRoot/dishes');
  if (!dishesDir.existsSync()) {
    stderr.writeln('dishes/ not found under "$repoRoot"');
    exit(66);
  }

  final mdFiles =
      dishesDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final recipes = <Map<String, dynamic>>[];
  var ok = 0;
  var skipped = 0;
  for (final file in mdFiles) {
    final rel = file.path.substring(dishesDir.path.length + 1);
    final recipe = parseHowToCookMarkdown(
      file.readAsStringSync(),
      relativePath: rel,
    );
    if (recipe == null ||
        recipe.ingredients.isEmpty ||
        recipe.steps.isEmpty) {
      skipped++;
      continue;
    }
    recipes.add(recipe.toJson());
    ok++;
  }

  File(outPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(recipes));
  stdout.writeln('Imported $ok recipes, skipped $skipped → $outPath');
}
```

- [ ] **Step 2: 运行脚本生成 asset**

```bash
git clone --depth 1 https://github.com/Anduin2017/HowToCook /tmp/HowToCook
dart run tool/import_howtocook.dart /tmp/HowToCook
```

Expected: 打印 `Imported <N> recipes, skipped <M> → assets/recipes/howtocook.json`，N 为数百量级（约 300+）。

- [ ] **Step 3: 验证产物**

```bash
test -s assets/recipes/howtocook.json && echo "non-empty OK"
python3 -c "import json;d=json.load(open('assets/recipes/howtocook.json'));print('count',len(d));print('sample',d[0]['name'],d[0]['category'],d[0]['difficulty'])"
```

Expected: `count` 为数百；`sample` 是中文菜名 + 中文类别 + 1-5 难度。若 count 异常少（<100），回头检查解析器对目录结构的兼容性，再重跑。

- [ ] **Step 4: 注册 asset**

修改 `apps/mobile/pubspec.yaml`，在 `flutter:` 的 `assets:` 列表（line 97-99）追加一行：

```yaml
  assets:
    - assets/icons/app_icon.png
    - google_fonts/
    - assets/recipes/
```

- [ ] **Step 5: 确认依赖解析正常**

Run: `flutter pub get`
Expected: 成功，无 asset 相关报错。

- [ ] **Step 6: 提交**

```bash
dart format tool/import_howtocook.dart
git add tool/import_howtocook.dart assets/recipes/howtocook.json pubspec.yaml
git commit -m "feat(recipes): 导入脚本 + 生成 HowToCook 本地食谱 asset"
```

---

## Task 3: LocalRecipeRepository

**Files:**
- Create: `apps/mobile/lib/storage/local_recipe_repository.dart`
- Create: `apps/mobile/test/local_recipe_repository_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// apps/mobile/test/local_recipe_repository_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/storage/local_recipe_repository.dart';

void main() {
  Recipe recipe(String id) => Recipe(
    id: id,
    name: '番茄炒蛋',
    category: '素菜',
    difficulty: 1,
    cookingMinutes: 15,
    description: '',
    ingredients: [RecipeIngredient(name: '番茄')],
    steps: const ['炒'],
  );

  test('loadAll 解析 asset json 为 Recipe 列表', () async {
    final json = jsonEncode([recipe('howtocook:vegetable_dish/番茄炒蛋').toJson()]);
    final repo = LocalRecipeRepository(loadString: (_) async => json);

    final recipes = await repo.loadAll();

    expect(recipes.single.id, 'howtocook:vegetable_dish/番茄炒蛋');
    expect(recipes.single.name, '番茄炒蛋');
  });

  test('loadAll 缓存结果，第二次不再读 asset', () async {
    var calls = 0;
    final json = jsonEncode([recipe('a').toJson()]);
    final repo = LocalRecipeRepository(
      loadString: (_) async {
        calls++;
        return json;
      },
    );

    await repo.loadAll();
    await repo.loadAll();

    expect(calls, 1);
  });

  test('asset 不是 JSON 数组时抛异常（让上层转 fetchFailed）', () async {
    final repo = LocalRecipeRepository(loadString: (_) async => '{}');
    expect(repo.loadAll(), throwsFormatException);
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/local_recipe_repository_test.dart`
Expected: FAIL —— `local_recipe_repository.dart` 不存在 / `LocalRecipeRepository` 未定义。

- [ ] **Step 3: 实现 repository**

```dart
// apps/mobile/lib/storage/local_recipe_repository.dart
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/recipe.dart';

const String howtocookAssetKey = 'assets/recipes/howtocook.json';

/// 从打包的 asset 读取 HowToCook 本地中文食谱，解析结果按实例缓存。
class LocalRecipeRepository {
  LocalRecipeRepository({Future<String> Function(String key)? loadString})
    : _loadString = loadString ?? rootBundle.loadString;

  final Future<String> Function(String key) _loadString;
  List<Recipe>? _cache;

  Future<List<Recipe>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await _loadString(howtocookAssetKey);
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('howtocook.json must be a JSON array');
    }
    final recipes = decoded
        .whereType<Map<String, dynamic>>()
        .map(Recipe.fromJson)
        .toList(growable: false);
    _cache = recipes;
    return recipes;
  }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/local_recipe_repository_test.dart`
Expected: PASS（3 个测试全绿）。

- [ ] **Step 5: 格式化 + 提交**

```bash
dart format lib/storage/local_recipe_repository.dart test/local_recipe_repository_test.dart
git add lib/storage/local_recipe_repository.dart test/local_recipe_repository_test.dart
git commit -m "feat(recipes): LocalRecipeRepository 读取本地食谱 asset"
```

---

## Task 4: provider 接线（切到本地库）

**Files:**
- Modify: `apps/mobile/lib/providers/recipe_provider.dart`
- Modify: `apps/mobile/test/provider_logic_test.dart`（`recipesProvider cache` group，约 1035-1119 行）

- [ ] **Step 1: 改写测试（`recipesProvider cache` group）**

把 `provider_logic_test.dart` 中整个 `group('recipesProvider cache', ...)`（约 1035-1175 行，含 5 个 TheMealDB 语义测试：无库存不搜 / 缓存命中 / 缓存保存 / client throws→空 / 全部失败→fetchFailed）**整体替换**为下面这一组（2 个测试）。本地库不依赖库存、总是返回全集，所以网络相关的缓存/库存语义随之删除（`LocalRecipeRepository` 的实例缓存已在 Task 3 覆盖）。新组改 override `localRecipeRepositoryProvider`：

```dart
  group('recipesProvider (local HowToCook)', () {
    test('返回本地仓库的全部食谱', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final repo = LocalRecipeRepository(
        loadString: (_) async => json.encode([
          _recipe('howtocook:a', '番茄炒蛋', ['番茄']).toJson(),
          _recipe('howtocook:b', '可乐鸡翅', ['鸡翅']).toJson(),
        ]),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, inventory: const []),
          localRecipeRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final recipes = await container.read(recipesProvider.future);

      expect(recipes.map((r) => r.id), containsAll(['howtocook:a', 'howtocook:b']));
    });

    test('加载失败时 recipes 为空且 fetchFailed 为真', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final repo = LocalRecipeRepository(
        loadString: (_) async => throw Exception('asset missing'),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, inventory: const []),
          localRecipeRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(recipesFetchProvider.future);

      expect(result.recipes, isEmpty);
      expect(result.fetchFailed, isTrue);
    });
  });
```

确保该测试文件顶部 import 了 `package:fresh_pantry/storage/local_recipe_repository.dart`（若无则添加）。`_recipe` / `_ingredient` 是该文件已有的本地 helper，沿用。

同时删除该文件里两处 TheMealDB 残留（改写后已无引用）：
- 顶部 `import 'package:fresh_pantry/services/themealdb_service.dart';`（line 14）
- 文件末尾 `class _FakeMealDbApi implements MealDbApi { ... }`（约 1289 行起整段）

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/provider_logic_test.dart`
Expected: FAIL —— `localRecipeRepositoryProvider` / `LocalRecipeRepository` 未定义（provider 尚未添加）。

- [ ] **Step 3: 改 `recipe_provider.dart`**

3a. 删除顶部这些 import / export / provider（它们都属于 TheMealDB 链）：

```dart
// 删除：
import '../data/food_knowledge.dart';
import '../services/themealdb_service.dart';
import '../storage/recipe_search_repo.dart';

export '../storage/recipe_search_repo.dart'
    show
        RecipeSearchRepository,
        recipeDetailsCacheStorageKey,
        recipeSearchCacheKeyFor;

final mealDbApiProvider = Provider<MealDbApi>(
  (ref) => const TheMealDbService(),
);

final recipeSearchRepositoryProvider = Provider<RecipeSearchRepository>((ref) {
  return RecipeSearchRepository(
    storage: ref.read(storageAdapterProvider),
    api: ref.watch(mealDbApiProvider),
  );
});
```

3b. 新增 import 与 provider（放在文件顶部 import 区 / provider 定义区）：

```dart
import '../storage/local_recipe_repository.dart';

final localRecipeRepositoryProvider = Provider<LocalRecipeRepository>(
  (ref) => LocalRecipeRepository(),
);
```

3c. 把 `recipesFetchProvider`（约 80-121 行，整段含库存翻译 + 逐词联网搜）替换为：

```dart
/// 探索 tab 的数据源：加载全部本地 HowToCook 中文食谱。
///
/// 返回 `({recipes, fetchFailed})` 形态以兼容探索 tab 既有的错误重试 UI：
/// asset 缺失 / 解析失败时 recipes 为空、fetchFailed 为真。按库存食材的
/// 匹配排序由 [recommendedRecipesProvider] 承担，对数据来源透明。
final recipesFetchProvider =
    FutureProvider<({List<Recipe> recipes, bool fetchFailed})>((ref) async {
      final repo = ref.watch(localRecipeRepositoryProvider);
      try {
        final recipes = await repo.loadAll();
        return (recipes: recipes, fetchFailed: false);
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint('Local recipe load failed: $e\n$stack');
        }
        return (recipes: <Recipe>[], fetchFailed: true);
      }
    });
```

> `kDebugMode` / `debugPrint` 已由文件顶部 `package:flutter/foundation.dart` 提供，无需新增 import。`recipesProvider`（取 `.recipes`）保持不变。

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/provider_logic_test.dart`
Expected: PASS（新 group 两个测试通过；其余原有测试不受影响）。

- [ ] **Step 5: 格式化 + 提交**

```bash
dart format lib/providers/recipe_provider.dart test/provider_logic_test.dart
git add lib/providers/recipe_provider.dart test/provider_logic_test.dart
git commit -m "feat(recipes): recipesFetchProvider 切到本地 HowToCook 库"
```

---

## Task 5: 删除 TheMealDB 调用链

**Files:**
- Delete: `apps/mobile/lib/services/themealdb_service.dart`
- Delete: `apps/mobile/lib/storage/recipe_search_repo.dart`
- Delete: `apps/mobile/test/themealdb_service_test.dart`

- [ ] **Step 1: 找出所有残留引用**

```bash
grep -rn "themealdb_service\|TheMealDbService\|MealDbApi\|recipe_search_repo\|RecipeSearchRepository\|mealDbApiProvider\|recipeSearchRepositoryProvider\|recipeDetailsCacheStorageKey\|recipeSearchCacheKeyFor" lib/ test/
```

Expected: 经核对，`recipes_screen_test` / `recommended_recipes_test` / `expiring_fallback_recipe_test` / `dashboard_screen_test` 均 override 上层的 `recipesProvider`（不碰 mealDbApi），**不受影响、无需改动**；`provider_logic_test` 的引用已在 Task 4 清理。所以 grep 结果应仅剩三个待删文件自身的定义。若出现预期外的引用，先处理再删。

- [ ] **Step 2: 确认其它 recipe 测试不受影响**

这些测试都 override `recipesProvider`，与底层数据源解耦，无需改动。运行确认：

Run: `flutter test test/recipes_screen_test.dart test/recommended_recipes_test.dart test/expiring_fallback_recipe_test.dart test/dashboard_screen_test.dart`
Expected: PASS。

- [ ] **Step 3: 删除三个文件**

```bash
git rm lib/services/themealdb_service.dart lib/storage/recipe_search_repo.dart test/themealdb_service_test.dart
```

- [ ] **Step 4: 静态分析确认无悬空引用**

Run: `flutter analyze`
Expected: No issues found（若报某文件仍引用已删符号，回到 Step 2 处理）。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "refactor(recipes): 删除 TheMealDB 调用链"
```

---

## Task 6: 关于页加开源致谢

**Files:**
- Modify: `apps/mobile/lib/screens/settings_screen.dart`（「更多」section，约 497-502 行）

> 说明：`SettingsScreen` 依赖多个 provider，整屏 widget 测试搭建成本高、收益低。本任务不写 widget 测试，靠 `flutter analyze` 保证编译 + Task 7 的人工/集成验证确认渲染。致谢文案是低风险静态 UI。

- [ ] **Step 1: 接入致谢行**

把「关于 FreshKeeper」行的 `isLast: true` 改为 `isLast: false`，并在其后新增一行：

```dart
                      _LinkRow(
                        label: '关于 FreshKeeper',
                        icon: Icons.info_outline_rounded,
                        onTap: () {},
                        isLast: false,
                      ),
                      _LinkRow(
                        label: '开源致谢',
                        sub: '探索菜谱数据来自 HowToCook（Unlicense）',
                        icon: Icons.favorite_outline_rounded,
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('开源致谢'),
                            content: const Text(
                              '探索 tab 的中文菜谱数据来自开源项目 '
                              'HowToCook（程序员做饭指南），以 Unlicense 公共领域协议发布。\n\n'
                              'https://github.com/Anduin2017/HowToCook',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('好的'),
                              ),
                            ],
                          ),
                        ),
                        isLast: true,
                      ),
```

> 若 `_LinkRow` 的 `sub` 参数名与此处不符，先 Read `_LinkRow` 定义（同文件内）核对字段名再填。

- [ ] **Step 2: 静态分析**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: No issues found。

- [ ] **Step 3: 格式化 + 提交**

```bash
dart format lib/screens/settings_screen.dart
git add lib/screens/settings_screen.dart
git commit -m "feat(settings): 加 HowToCook 开源致谢"
```

---

## Task 7: 全量验证

- [ ] **Step 1: 静态分析全绿**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: All tests passed. 重点关注 `recipes_screen_test.dart`、`recommended_recipes_test.dart`、`expiring_fallback_recipe_test.dart`、`provider_logic_test.dart` 全绿。

- [ ] **Step 3: 手动冒烟（探索 tab）**

```bash
flutter run
```

人工确认：菜谱 tab →「探索」展示中文家常菜（菜名/食材/步骤均中文）；搜索框可按中文菜名/食材过滤；时间筛选（≤15/≤30）有效；卡片显示「匹配库存食材数」；无图卡片显示餐具占位图标。设置 →「更多」→「开源致谢」可弹窗。

- [ ] **Step 4: 最终提交（若冒烟中有微调）**

```bash
git add -A
git commit -m "chore(recipes): 探索 tab 切换 HowToCook 收尾"
```

---

## 完成标准

- 探索 tab 全部为中文家常菜，离线可用，无网络/无 key。
- 「现有 / 用临期」tab 的按库存食材推荐照常工作（数据来自本地库）。
- `flutter analyze` 与 `flutter test` 全绿。
- TheMealDB 调用链已彻底删除，无悬空引用。
- 设置页含 HowToCook 开源致谢。

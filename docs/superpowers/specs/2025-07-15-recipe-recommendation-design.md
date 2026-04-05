# 食谱推荐功能设计规格

## 概述

为 Fresh Pantry（食材管家）集成基于 HowToCook 开源项目的中餐食谱推荐功能。核心目标：

1. **减少浪费**：优先推荐能消耗库存中临期食材的食谱
2. **日常做饭灵感**：根据当前全部库存推荐可做的菜，解决"今天吃什么"

### 设计原则

- 本地内置数据，离线可用，零网络依赖
- 不新增 Tab，不改导航结构，优化现有 Dashboard 入口
- 精简版（YAGNI）：不做搜索、收藏、购物车集成

---

## 1. 数据层

### 1.1 Recipe 模型升级

现有 `Recipe` 模型的 `ingredients` 是 `List<String>`，无法区分食材名与用量。升级为结构化模型：

```dart
class RecipeIngredient {
  final String name;     // 标准化食材名，如"鸡蛋"
  final String amount;   // 用量，如"3个" 或 "200g"
}

class Recipe {
  final String id;
  final String name;           // 菜名，如"西红柿炒鸡蛋"
  final String category;       // 分类：素菜/荤菜/水产/早餐/主食/汤与粥/甜品/饮料/酱料/半成品加工
  final int difficulty;        // 难度 0-5（星级，对应 HowToCook 的 ★ 数量）
  final int cookingMinutes;    // 烹饪时间（分钟）
  final String description;    // 一句话简介
  final List<RecipeIngredient> ingredients; // 结构化食材列表
  final List<String> steps;    // 烹饪步骤
  final List<String> tags;     // 标签，如 ["快手菜", "下饭菜"]
}
```

**变更点**：
- `ingredients` 从 `List<String>` 改为 `List<RecipeIngredient>`
- 新增 `category`（对应 HowToCook 的 10 大分类）和 `difficulty`（0-5 星）
- 新增 `fromJson()` 工厂构造函数
- `imageUrl` 字段保留但设为空字符串（HowToCook 无图片数据）

### 1.2 ScoredRecipe 辅助类

```dart
class ScoredRecipe {
  final Recipe recipe;
  final double score;
  final int matchedCount;
  final int expiringMatchedCount;
}
```

UI 可直接展示"匹配 3/5 种食材，其中 2 种即将过期"。

### 1.3 数据文件

- 路径：`assets/data/recipes.json`
- 内容：约 60 道精选中餐家常菜，预处理为结构化 JSON
- 在 `pubspec.yaml` 中声明 `assets/data/`

#### JSON 格式

```json
[
  {
    "id": "xihongshi-chao-jidan",
    "name": "西红柿炒鸡蛋",
    "category": "素菜",
    "difficulty": 2,
    "cookingMinutes": 15,
    "description": "经典家常菜，酸甜可口",
    "ingredients": [
      { "name": "西红柿", "amount": "2个(约300g)" },
      { "name": "鸡蛋", "amount": "3个" },
      { "name": "食用油", "amount": "15ml" },
      { "name": "盐", "amount": "3g" },
      { "name": "糖", "amount": "5g" }
    ],
    "steps": [
      "西红柿洗净，切成小块",
      "鸡蛋打散，加少许盐搅匀",
      "锅中倒油，油热后倒入蛋液，炒至凝固盛出",
      "锅中再加少许油，放入西红柿翻炒至出汁",
      "加入糖和盐调味，倒入炒好的鸡蛋翻炒均匀即可"
    ],
    "tags": ["快手菜", "下饭菜", "新手友好"]
  }
]
```

### 1.4 菜谱选取范围

从 HowToCook 的 305 道菜中精选约 60 道，覆盖各分类：

| 分类 | 数量 | 示例 |
|------|------|------|
| 素菜 | ~10 | 西红柿炒鸡蛋、炒青菜、拍黄瓜、酸辣土豆丝、地三鲜 |
| 荤菜 | ~15 | 红烧肉、宫保鸡丁、回锅肉、糖醋排骨、鱼香肉丝 |
| 水产 | ~5 | 清蒸鲈鱼、红烧鱼、水煮鱼 |
| 早餐 | ~5 | 茶叶蛋、煎饺、葱花蛋饼 |
| 主食 | ~8 | 蛋炒饭、西红柿鸡蛋面、饺子、炒面 |
| 汤与粥 | ~6 | 西红柿鸡蛋汤、皮蛋瘦肉粥、紫菜蛋花汤 |
| 甜品 | ~4 | 双皮奶、红糖姜茶 |
| 饮料 | ~3 | 奶茶、酸梅汤 |
| 酱料 | ~2 | 油泼辣子、葱油 |
| 半成品 | ~2 | 速冻水饺 |

**选取原则**：优先选食材与 App 现有分类（新鲜蔬果、肉类与海鲜、乳制品与蛋类等）重叠度高的菜谱。

### 1.5 食材名称标准化

JSON 中的 `RecipeIngredient.name` 与用户库存中常见的食材名对齐：

```
"西红柿" / "番茄" → 统一用 "西红柿"
"鸡蛋" / "蛋" → 统一用 "鸡蛋"
"生抽" / "酱油" → 统一用 "生抽"
```

标准化在编写 JSON 数据时完成，无需运行时映射。

### 1.6 RecipeService

新建 `lib/services/recipe_service.dart`：

```dart
class RecipeService {
  List<Recipe>? _cache;

  Future<List<Recipe>> loadRecipes(AssetBundle bundle) async {
    if (_cache != null) return _cache!;
    final jsonStr = await bundle.loadString('assets/data/recipes.json');
    final List<dynamic> jsonList = json.decode(jsonStr);
    _cache = jsonList.map((j) => Recipe.fromJson(j)).toList();
    return _cache!;
  }
}
```

- 非 static，可测试
- 首次加载后内存缓存
- 通过 `AssetBundle` 参数注入，便于测试

---

## 2. 推荐算法

### 2.1 评分公式

```
score = baseMatchScore + expiryBonus

baseMatchScore = matchedCount / totalIngredientCount    (0.0 ~ 1.0)
expiryBonus    = expiringMatchedCount * 0.15            (每个临期食材 +0.15)
```

- `matchedCount`：库存中拥有的食材数量
- `totalIngredientCount`：食谱要求的食材总数
- `expiringMatchedCount`：匹配到的食材中，状态为 `expiringSoon` 或 `expired` 的数量

**示例**：5 种食材的菜，库存有 3 种（2 种临期）→ `3/5 + 2×0.15 = 0.9`

### 2.2 食材匹配逻辑

现有匹配使用粗暴的 substring，会误匹配。改进为两级匹配：

1. **精确匹配优先**：`inventory.name == recipeIngredient.name`
2. **包含匹配兜底**：仅当精确匹配失败时使用 substring，且要求最短方**至少 2 个字符**（避免"油"、"盐"等单字误匹配）

### 2.3 Provider 结构

```
recipeServiceProvider (Provider<RecipeService>)
  └── 单例 RecipeService 实例

recipesProvider (FutureProvider<List<Recipe>>)
  └── 调用 recipeServiceProvider.loadRecipes()

recommendedRecipesProvider (Provider<AsyncValue<List<ScoredRecipe>>>)
  └── 依赖 recipesProvider + inventoryProvider
  └── 对每道菜执行匹配 + 评分
  └── 按 score 降序排列
```

---

## 3. UI 变更

### 3.1 Dashboard 变更

#### CuratorsTipCard 升级

现有：显示硬编码文本推荐。

改为：显示排名第一的 `ScoredRecipe`，展示：
- 菜名
- "匹配 X/Y 种食材"
- 如果 `expiringMatchedCount > 0`，显示橙色标签"可消耗 N 种临期食材"
- 点击仍然导航到 `RecipeDetailScreen`

#### "食谱推荐" 按钮

保持不变，点击弹出 bottom sheet。

### 3.2 Bottom Sheet 变更

#### 分区展示

1. **"消耗临期食材" 区**（顶部，仅当有 `expiringMatchedCount > 0` 的菜谱时显示）：
   - 橙色/警示色调标题
   - 最多展示 3 道菜
2. **"推荐菜谱" 区**（下方）：
   - 所有菜谱按 score 降序排列
   - 正常列表

#### RecipeCard 信息增强

现有：缩略图 + 菜名 + 描述 + 烹饪时间 + 匹配数

新增：
- 难度星级显示（★★★）
- 分类标签（如"荤菜"）
- 临期食材标记：如果 `expiringMatchedCount > 0`，显示小橙色徽章"可消耗临期"

#### 空状态

如果库存为空导致无推荐，显示友好提示："添加库存食材后，将为你推荐可做的菜谱"

### 3.3 RecipeDetailScreen 变更

#### 食材列表增强

每个食材显示所需用量（来自 `RecipeIngredient.amount`）：
- 库存中有：绿色 ✓
- 库存中有且临期：橙色 ✓ + "临期" 标签
- 库存中没有：灰色 ○

#### 难度与分类

标题下方显示 ★ 难度星级和分类标签。

#### 移除 Hero 图片

因为 HowToCook 无图片数据，将 `SliverAppBar` 的 hero 图片改为纯色/渐变背景 + 分类图标的简洁 header。

---

## 4. 文件结构

### 新增文件

| 文件 | 用途 |
|------|------|
| `assets/data/recipes.json` | 60 道精选菜谱的结构化 JSON 数据 |
| `lib/services/recipe_service.dart` | 加载 + 缓存 recipes.json |

### 修改文件

| 文件 | 变更 |
|------|------|
| `lib/models/recipe.dart` | 升级 Recipe 模型 + 新增 RecipeIngredient + ScoredRecipe |
| `lib/providers/recipe_provider.dart` | 重写为 FutureProvider + 新推荐算法 |
| `lib/screens/recipe_detail_screen.dart` | 适配新 Recipe 模型，增强食材/难度展示 |
| `lib/widgets/recipe_card.dart` | 增加难度/分类/临期标记 |
| `lib/widgets/dashboard/curators_tip_card.dart` | 使用 ScoredRecipe 数据 |
| `lib/screens/dashboard_screen.dart` | Bottom sheet 分区展示逻辑 |
| `lib/data/mock_data.dart` | 移除 mock recipes 数据 |
| `pubspec.yaml` | 声明 `assets/data/` |

### 不新增的

- 不新增 screen 文件（不加 Tab）
- 不新增 navigation 逻辑
- 不新增 persistence（食谱数据只读）

---

## 5. 不做的事（YAGNI）

- ❌ 食谱搜索/筛选功能
- ❌ 收藏/保存功能
- ❌ 缺失食材加入购物清单
- ❌ 食谱图片（HowToCook 无图片资源）
- ❌ 在线 API 集成（Spoonacular、TheMealDB 等）
- ❌ 生成预处理脚本（第一版手写 JSON）

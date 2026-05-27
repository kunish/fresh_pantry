import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';
import '../models/recipe.dart';
import 'food_categories.dart';

class MockData {
  // Generic chef avatar via UI Avatars (no external dependency)
  static const profileImageUrl =
      'https://ui-avatars.com/api/?name=主厨&background=8B4513&color=fff&size=128&font-size=0.5';

  static const inventoryItems = [
    Ingredient(
      name: '传家宝番茄',
      quantity: '4 个',
      unit: '800g',
      imageUrl:
          'https://images.unsplash.com/photo-1546470427-0d4db154ceb8?w=400&h=400&fit=crop',
      freshnessPercent: 0.85,
      state: FreshnessState.fresh,
      expiryLabel: '新鲜',
      category: FoodCategories.freshProduce,
      storage: IconType.fridge,
    ),
    Ingredient(
      name: '有机全脂牛奶',
      quantity: '1 瓶',
      unit: '1L',
      imageUrl:
          'https://images.unsplash.com/photo-1563636619-e9143da7973b?w=400&h=400&fit=crop',
      freshnessPercent: 0.30,
      state: FreshnessState.expiringSoon,
      expiryLabel: '2天后过期',
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
    ),
    Ingredient(
      name: '嫩菠菜',
      quantity: '1 袋',
      unit: '250g',
      imageUrl:
          'https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=400&h=400&fit=crop',
      freshnessPercent: 0.05,
      state: FreshnessState.expired,
      expiryLabel: '昨日已过期',
      category: FoodCategories.freshProduce,
      storage: IconType.fridge,
    ),
    Ingredient(
      name: '散养鸡蛋',
      quantity: '12 个',
      unit: 'A级',
      imageUrl:
          'https://images.unsplash.com/photo-1582722872445-44dc5f7e3c8f?w=400&h=400&fit=crop',
      freshnessPercent: 0.95,
      state: FreshnessState.fresh,
      expiryLabel: '新鲜',
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
    ),
    Ingredient(
      name: '手工法棍',
      quantity: '1 条',
      unit: '新鲜烘焙',
      imageUrl:
          'https://images.unsplash.com/photo-1549931319-a545753467c8?w=400&h=400&fit=crop',
      freshnessPercent: 0.45,
      state: FreshnessState.expiringSoon,
      expiryLabel: '明天前食用',
      category: FoodCategories.other,
      storage: IconType.pantry,
    ),
    Ingredient(
      name: '肋眼牛排',
      quantity: '2 块',
      unit: '600g',
      imageUrl:
          'https://images.unsplash.com/photo-1588347818481-0e7ca5753376?w=400&h=400&fit=crop',
      freshnessPercent: 0.70,
      state: FreshnessState.fresh,
      expiryLabel: '新鲜',
      category: FoodCategories.meatAndSeafood,
      storage: IconType.fridge,
    ),
  ];

  static const recentAdditions = [
    Ingredient(
      name: '传家宝胡萝卜',
      quantity: '500g',
      unit: '2小时前添加',
      imageUrl:
          'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=400&h=400&fit=crop',
      freshnessPercent: 0.95,
      state: FreshnessState.fresh,
      category: FoodCategories.freshProduce,
    ),
    Ingredient(
      name: '意式黑醋酱',
      quantity: '250ml',
      unit: '昨天添加',
      imageUrl:
          'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=400&h=400&fit=crop',
      freshnessPercent: 1.0,
      state: FreshnessState.fresh,
      category: FoodCategories.herbsAndSpices,
    ),
  ];

  static const shoppingItems = [
    ShoppingItem(
      id: 'si_1',
      name: '有机传家宝番茄',
      detail: '4个 \u2022 农贸市场',
      imageUrl:
          'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=400&h=400&fit=crop',
      category: FoodCategories.freshProduce,
    ),
    ShoppingItem(
      id: 'si_2',
      name: '野生芝麻菜',
      detail: '1袋 (250g)',
      imageUrl:
          'https://images.unsplash.com/photo-1515696955266-4f67e13219e8?w=400&h=400&fit=crop',
      category: FoodCategories.freshProduce,
    ),
    ShoppingItem(
      id: 'si_3',
      name: '哈斯牛油果',
      detail: '2个 \u2022 已熟',
      imageUrl:
          'https://images.unsplash.com/photo-1523049673857-eb18f1d7b578?w=400&h=400&fit=crop',
      category: FoodCategories.freshProduce,
    ),
    ShoppingItem(
      id: 'si_4',
      name: '马尔顿海盐片',
      detail: '1盒 (250g)',
      imageUrl:
          'https://images.unsplash.com/photo-1518110925495-5fe2c8b2be25?w=400&h=400&fit=crop',
      category: FoodCategories.herbsAndSpices,
      isChecked: true,
    ),
    ShoppingItem(
      id: 'si_5',
      name: 'A2全脂牛奶',
      detail: '1升',
      imageUrl:
          'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=400&h=400&fit=crop',
      category: FoodCategories.dairyAndEggs,
    ),
  ];

  static const quickSuggestions = ['牛奶', '鸡蛋', '酸面包', '黄油'];

  static final recipes = [
    Recipe(
      id: 'r1',
      name: '经典卡博纳拉意面',
      category: '主食',
      difficulty: 2,
      description: '用鸡蛋、帕玛森芝士和培根制作的意式经典奶油意面，浓郁顺滑。',
      cookingMinutes: 25,
      ingredients: [
        RecipeIngredient(name: '散养鸡蛋', amount: '2个'),
        RecipeIngredient(name: '意大利面', amount: '200g'),
        RecipeIngredient(name: '培根', amount: '100g'),
        RecipeIngredient(name: '帕玛森芝士', amount: '50g'),
        RecipeIngredient(name: '黑胡椒', amount: '适量'),
      ],
      steps: [
        '大锅煮水，加盐，煮意面至弹牙',
        '培根切丁，中火煎至焦脆',
        '鸡蛋打散，加入磨碎的帕玛森芝士搅拌均匀',
        '意面沥水后加入培根锅中，离火',
        '倒入蛋液快速翻拌，利用余温使蛋液变稠',
        '撒上黑胡椒和额外的芝士即可',
      ],
      tags: ['蛋白质', '谷物'],
    ),
    Recipe(
      id: 'r2',
      name: '番茄牛排配菠菜沙拉',
      category: '主菜',
      difficulty: 3,
      description: '煎至完美的肋眼牛排，搭配传家宝番茄和新鲜菠菜沙拉。',
      cookingMinutes: 20,
      ingredients: [
        RecipeIngredient(name: '肋眼牛排', amount: '2块'),
        RecipeIngredient(name: '传家宝番茄', amount: '2个'),
        RecipeIngredient(name: '嫩菠菜', amount: '100g'),
        RecipeIngredient(name: '橄榄油', amount: '2勺'),
        RecipeIngredient(name: '海盐', amount: '适量'),
      ],
      steps: [
        '牛排提前30分钟取出回温，两面撒海盐',
        '铸铁锅大火加热，放入牛排煎3分钟翻面',
        '根据喜好煎至五分熟，静置5分钟',
        '番茄切片，菠菜洗净沥干',
        '番茄和菠菜摆盘，淋上橄榄油',
        '牛排切片摆上，撒上现磨黑胡椒',
      ],
      tags: ['蛋白质', '蔬菜'],
    ),
    Recipe(
      id: 'r3',
      name: '法棍牛奶布丁',
      category: '甜品',
      difficulty: 1,
      description: '用即将过期的法棍和牛奶制作的甜品，减少浪费又美味。',
      cookingMinutes: 45,
      ingredients: [
        RecipeIngredient(name: '手工法棍', amount: '1条'),
        RecipeIngredient(name: '有机全脂牛奶', amount: '500ml'),
        RecipeIngredient(name: '散养鸡蛋', amount: '3个'),
        RecipeIngredient(name: '白糖', amount: '60g'),
        RecipeIngredient(name: '香草精', amount: '1勺'),
      ],
      steps: [
        '法棍切成2cm小块，放入烤盘',
        '牛奶、鸡蛋、白糖和香草精混合搅匀',
        '蛋奶液倒入烤盘浸泡法棍20分钟',
        '烤箱预热180°C',
        '烤30-35分钟至表面金黄',
        '取出稍凉后即可享用',
      ],
      tags: ['谷物', '乳制品'],
    ),
  ];
}

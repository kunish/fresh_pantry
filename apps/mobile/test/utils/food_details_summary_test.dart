import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/food_details.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/storage/food_details_repo.dart';
import 'package:fresh_pantry/utils/food_details_summary.dart';

FoodDetails _details({
  String description = '',
  String category = '',
  IconType storage = IconType.fridge,
  int? shelfLifeDays,
}) =>
    FoodDetails(
      displayName: '番茄',
      description: description,
      imageUrl: null,
      category: category,
      storage: storage,
      shelfLifeDays: shelfLifeDays,
      source: 'test',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );

void main() {
  group('isPlaceholderFoodDescription', () {
    test('empty is a placeholder', () {
      expect(isPlaceholderFoodDescription(''), isTrue);
      expect(isPlaceholderFoodDescription('   '), isTrue);
    });

    test('producer templates are placeholders', () {
      expect(isPlaceholderFoodDescription('Open Food Facts 记录的蔬菜食品。'), isTrue);
      expect(isPlaceholderFoodDescription('建议存放在冰箱，约 5 天内食用。'), isTrue);
      expect(isPlaceholderFoodDescription('暂无联网详情，已保留本地库存中的食材信息。'), isTrue);
    });

    test('a real description is not a placeholder', () {
      expect(isPlaceholderFoodDescription('富含维生素 C 的红色浆果'), isFalse);
    });
  });

  group('foodDetailsSummary', () {
    test('joins useful parts with a middot', () {
      final s = foodDetailsSummary(_details(
        description: '富含维生素 C',
        category: '蔬菜',
        storage: IconType.fridge,
        shelfLifeDays: 5,
      ));
      expect(s, '富含维生素 C · 蔬菜 · 冰箱保存 · 约 5 天');
    });

    test('omits placeholder description', () {
      final s = foodDetailsSummary(_details(
        description: '暂无联网详情，已保留本地库存中的食材信息。',
        category: '蔬菜',
        storage: IconType.fridge,
      ));
      expect(s, '蔬菜 · 冰箱保存');
    });

    test('omits non-positive shelf life', () {
      final s = foodDetailsSummary(_details(
        category: '调味料',
        storage: IconType.pantry,
        shelfLifeDays: 0,
      ));
      expect(s, '调味料 · 食品柜保存');
    });
  });
}

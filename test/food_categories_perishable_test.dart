import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';

void main() {
  group('FoodCategories.isPerishable', () {
    test('果蔬生鲜 / 肉类海鲜 / 乳品蛋类 are perishable', () {
      expect(FoodCategories.isPerishable(FoodCategories.freshProduce), isTrue);
      expect(FoodCategories.isPerishable(FoodCategories.meatAndSeafood), isTrue);
      expect(FoodCategories.isPerishable(FoodCategories.dairyAndEggs), isTrue);
    });

    test('香料草本 / 其他 are non-perishable', () {
      expect(FoodCategories.isPerishable(FoodCategories.herbsAndSpices), isFalse);
      expect(FoodCategories.isPerishable(FoodCategories.other), isFalse);
    });

    test('null / unknown defaults to non-perishable (safe default)', () {
      expect(FoodCategories.isPerishable(null), isFalse);
      expect(FoodCategories.isPerishable('garbage'), isFalse);
    });

    test('normalises aliases before checking (e.g. 蔬菜 → 果蔬生鲜)', () {
      expect(FoodCategories.isPerishable('蔬菜'), isTrue);
      expect(FoodCategories.isPerishable('肉类'), isTrue);
    });
  });
}

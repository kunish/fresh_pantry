import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/data/food_knowledge.dart';

void main() {
  group('FoodCategories', () {
    test('exposes the fixed app categories in display order', () {
      expect(FoodCategories.values, const [
        '乳品蛋类',
        '果蔬生鲜',
        '肉类海鲜',
        '香料草本',
        '其他',
      ]);
    });

    test('normalizes legacy and custom categories into the fixed set', () {
      expect(FoodCategories.normalize('乳制品与蛋类'), FoodCategories.dairyAndEggs);
      expect(FoodCategories.normalize('新鲜蔬果'), FoodCategories.freshProduce);
      expect(FoodCategories.normalize('蔬菜'), FoodCategories.freshProduce);
      expect(FoodCategories.normalize('肉类与海鲜'), FoodCategories.meatAndSeafood);
      expect(FoodCategories.normalize('香料与草本'), FoodCategories.herbsAndSpices);
      expect(FoodCategories.normalize('自定义分类'), FoodCategories.other);
      expect(FoodCategories.normalize('  '), isNull);
    });
  });

  group('FoodKnowledge.categoryFor', () {
    test('returns the stable category for known ingredients', () {
      expect(FoodKnowledge.categoryFor('鸡蛋'), FoodCategories.dairyAndEggs);
      expect(FoodKnowledge.categoryFor('大米'), FoodCategories.other);
      expect(FoodKnowledge.categoryFor('黑胡椒'), FoodCategories.herbsAndSpices);
    });

    test('uses the longest keyword match before broader matches', () {
      expect(FoodKnowledge.categoryFor('番茄酱'), FoodCategories.other);
    });

    test('falls back for blank and unknown names', () {
      expect(FoodKnowledge.categoryFor(''), FoodCategories.other);
      expect(FoodKnowledge.categoryFor('  '), FoodCategories.other);
      expect(FoodKnowledge.categoryFor('未知食材'), FoodCategories.other);
    });

    test('normalizes fallback categories into the fixed set', () {
      expect(
        FoodKnowledge.categoryFor('未知食材', fallback: '自定义分类'),
        FoodCategories.other,
      );
      expect(
        FoodKnowledge.categoryFor('未知食材', fallback: '蔬菜'),
        FoodCategories.freshProduce,
      );
    });
  });
}

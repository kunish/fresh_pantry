import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
      expect(recipe.cookingMinutes, 40);
      expect(recipe.description, contains('可乐鸡翅'));
      expect(recipe.ingredients.map((i) => i.name), contains('鸡翅中'));
      expect(recipe.ingredients.map((i) => i.name), contains('可乐'));
      expect(recipe.ingredients.length, 8);
      expect(recipe.ingredients.every((i) => i.amount.isEmpty), isTrue);
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
      expect(recipe.cookingMinutes, 60);
      expect(recipe.ingredients.map((i) => i.name), contains('兔肉'));
      expect(recipe.ingredients.length, 17);
      expect(recipe.steps.length, 10);
    });

    test('无 # 标题 → null', () {
      expect(
        parseHowToCookMarkdown(
          '没有标题\n\n## 操作\n\n1. 做菜',
          relativePath: 'meat_dish/x.md',
        ),
        isNull,
      );
    });

    test('无「## 操作」段 → null（非菜谱，如 README）', () {
      expect(
        parseHowToCookMarkdown(
          '# 介绍\n\n一些说明文字',
          relativePath: 'meat_dish/README.md',
        ),
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

    test('无难度行 → difficulty 0、cookingMinutes 兜底 30', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试菜的做法\n\n## 必备原料和工具\n\n- 盐\n\n## 操作\n\n1. 做',
        relativePath: 'vegetable_dish/测试菜.md',
      );
      expect(recipe!.difficulty, 0);
      expect(recipe.cookingMinutes, 30);
    });

    test('剔除工具，仅保留食材：烙饼去掉「电饼铛」', () {
      final recipe = parseHowToCookMarkdown(
        fixture('烙饼.md'),
        relativePath: 'staple/烙饼/烙饼.md',
      );
      final names = recipe!.ingredients.map((i) => i.name).toList();
      expect(names, ['油', '面粉']);
      expect(names, isNot(contains('电饼铛')));
    });

    test('步骤清理内联 markdown：保留链接文字，去掉链接目标与图片', () {
      final recipe = parseHowToCookMarkdown(
        fixture('烙饼.md'),
        relativePath: 'staple/烙饼/烙饼.md',
      );
      final step2 = recipe!.steps[1];
      expect(step2, contains('请查看小技巧中的油酥做法'));
      expect(step2, isNot(contains('[小技巧]')));
      expect(step2, isNot(contains('](')));
      expect(step2, isNot(contains('.md')));
      for (final s in recipe.steps) {
        expect(s.contains('!['), isFalse, reason: '步骤不应残留图片 markdown: $s');
        expect(
          RegExp(r'\]\([^)]*\)').hasMatch(s),
          isFalse,
          reason: '步骤不应残留链接 markdown: $s',
        );
      }
    });

    test('生成 GitHub LFS media 成品图 URL（优先「成品/预览」命名图）', () {
      final recipe = parseHowToCookMarkdown(
        fixture('烙饼.md'),
        relativePath: 'staple/烙饼/烙饼.md',
      );
      final expected =
          'https://media.githubusercontent.com/media/Anduin2017/HowToCook/master/dishes/'
          '${['staple', '烙饼', '成品.jpg'].map(Uri.encodeComponent).join('/')}';
      expect(recipe!.imageUrl, expected);
    });

    test('平铺型剔除工具/数量：糖醋鲤鱼去掉盆/菜刀/锅铲，香菜去掉「一颗」', () {
      final recipe = parseHowToCookMarkdown(
        fixture('糖醋鲤鱼.md'),
        relativePath: 'aquatic/糖醋鲤鱼/糖醋鲤鱼.md',
      );
      final names = recipe!.ingredients.map((i) => i.name).toList();
      expect(names, contains('鲤鱼'));
      expect(names, contains('香菜'));
      expect(names, isNot(contains('香菜一颗')));
      expect(
        names.any(
          (n) =>
              n.contains('刀') ||
              n.contains('笊篱') ||
              n.endsWith('锅') ||
              n.endsWith('盆'),
        ),
        isFalse,
        reason: '不应残留工具项: $names',
      );
    });

    test('子标题分流：戚风蛋糕只取「原料」段，排除「工具」段', () {
      final recipe = parseHowToCookMarkdown(
        fixture('戚风蛋糕.md'),
        relativePath: 'dessert/戚风蛋糕/戚风蛋糕.md',
      );
      final names = recipe!.ingredients.map((i) => i.name).toList();
      expect(names.length, 6);
      expect(names, contains('鸡蛋'));
      expect(names, contains('低筋面粉'));
      expect(names, contains('柠檬汁或白醋')); // [可选] 前缀剥离
      for (final tool in ['烤箱', '打蛋器', '刮刀']) {
        expect(names, isNot(contains(tool)));
      }
      expect(names.any((n) => n.contains('模具')), isFalse);
    });

    test('丢弃以冒号结尾的分组标题行，保留其下子项', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试的做法\n\n## 必备原料和工具\n\n'
        '- 袋装螺蛳粉一包，其中应该包含：\n  - 米粉\n  - 汤料包\n\n'
        '## 操作\n\n1. 煮',
        relativePath: 'staple/测试.md',
      );
      final names = recipe!.ingredients.map((i) => i.name).toList();
      expect(names, isNot(contains('袋装螺蛳粉一包，其中应该包含：')));
      expect(names, contains('米粉'));
      expect(names, contains('汤料包'));
    });

    test('一行顿号分隔多食材拆开（简易红烧肉），括号注释各自剥离', () {
      final recipe = parseHowToCookMarkdown(
        fixture('简易红烧肉.md'),
        relativePath: 'meat_dish/红烧肉/简易红烧肉.md',
      );
      final names = recipe!.ingredients.map((i) => i.name).toList();
      expect(
        names,
        containsAll([
          '大肉', '鸡蛋', '豆皮', // 主料：括号注释（可选）已各自剥离
          '生姜', '冰糖', '生抽', '老抽', '料酒', '香叶', '八角', '盐', '水', '葱',
        ]),
      );
      expect(names.any((n) => n.contains('、')), isFalse, reason: '不应有合并项: $names');
      expect(names.any((n) => n.contains('磨的锋利')), isFalse); // 「注：…」旁注丢弃
      expect(names.length, 13);
    });

    test('逗号分隔多食材也拆开，并过滤说明句碎片', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试的做法\n\n## 必备原料和工具\n\n'
        '- 油，盐，生抽，蚝油，料酒\n'
        '- 牛奶 50-100g，能够将燕麦搅拌粘稠即可\n\n'
        '## 操作\n\n1. 做',
        relativePath: 'meat_dish/x.md',
      );
      final names = recipe!.ingredients.map((i) => i.name).toList();
      expect(names, containsAll(['油', '盐', '生抽', '蚝油', '料酒', '牛奶']));
      expect(
        names.any((n) => n.contains('即可') || n.contains('能够')),
        isFalse,
        reason: '说明句碎片应被过滤: $names',
      );
    });

    test('食材行清理图片/链接 markdown 与前置数量', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试的做法\n\n## 必备原料和工具\n\n'
        '- 泡发好的海参![海参](./x.jpg)\n'
        '- 125ml 淡奶油\n'
        '- 牛排，参见[如何选择](./y.md)\n\n'
        '## 操作\n\n1. 做',
        relativePath: 'meat_dish/x.md',
      );
      final names = recipe!.ingredients.map((i) => i.name).toList();
      expect(names, contains('泡发好的海参'));
      expect(names, contains('淡奶油'));
      expect(names, contains('牛排'));
      expect(
        names.any(
          (n) =>
              n.contains('![') ||
              n.contains('](') ||
              n.contains('参见') ||
              RegExp(r'\d').hasMatch(n),
        ),
        isFalse,
        reason: 'markdown/数量残留: $names',
      );
    });

    test('加号分隔多食材也拆开', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试的做法\n\n## 必备原料和工具\n\n'
        '- 盐 + 鸡精 + 十三香\n\n## 操作\n\n1. 做',
        relativePath: 'meat_dish/x.md',
      );
      final names = recipe!.ingredients.map((i) => i.name).toList();
      expect(names, ['盐', '鸡精', '十三香']);
    });

    test('图片路径含括号文件名不被截断（冰粉：石凉粉(冰粉)成品1.jpg）', () {
      final recipe = parseHowToCookMarkdown(
        '# 冰粉的做法\n\n'
        '![石凉粉(冰粉)成品1](./石凉粉(冰粉)成品1.jpg)\n\n'
        '## 必备原料和工具\n\n- 冰粉粉\n\n## 操作\n\n1. 做',
        relativePath: 'drink/冰粉/冰粉.md',
      );
      final expected =
          'https://media.githubusercontent.com/media/Anduin2017/HowToCook/master/dishes/'
          '${['drink', '冰粉', '石凉粉(冰粉)成品1.jpg'].map(Uri.encodeComponent).join('/')}';
      expect(recipe!.imageUrl, expected);
    });

    test('步骤内联链接 URL 含括号时整体删除，不残留右括号与扩展名', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试的做法\n\n## 必备原料和工具\n\n- 盐\n\n'
        '## 操作\n\n1. 详见[说明](./a(b).md)继续操作',
        relativePath: 'meat_dish/x.md',
      );
      expect(recipe!.steps.first, '详见说明继续操作');
    });
  });
}

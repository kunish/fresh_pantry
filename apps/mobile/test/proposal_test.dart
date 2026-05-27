import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';

void main() {
  group('IntakeProposal', () {
    test('defaults action to newRow with no merge target', () {
      final p = IntakeProposal(
        id: 'p1',
        name: '苹果',
        quantity: '5',
        unit: '个',
        category: FoodCategories.freshProduce,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      );
      expect(p.action, IntakeAction.newRow);
      expect(p.mergeTargetId, isNull);
      expect(p.selected, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      final p = IntakeProposal(
        id: 'p1',
        name: '苹果',
        quantity: '5',
        unit: '个',
        category: FoodCategories.freshProduce,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      );
      final p2 = p.copyWith(quantity: '7', userEdited: true);
      expect(p2.quantity, '7');
      expect(p2.name, '苹果');
      expect(p2.userEdited, isTrue);
    });
  });

  group('DeductionProposal', () {
    test('defaults action to deduct with first candidate chosen', () {
      final p = DeductionProposal(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '50g',
        candidates: const [
          DeductionCandidate(
              inventoryRowIndex: 2, displayLabel: '葱 1把 (剩 5 天)'),
        ],
        chosenIndex: 2,
        deductAmount: '1',
      );
      expect(p.action, DeductionAction.deduct);
      expect(p.chosenIndex, 2);
    });

    test('action=skip when no candidates', () {
      final p = DeductionProposal.empty(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '50g',
      );
      expect(p.action, DeductionAction.skip);
      expect(p.candidates, isEmpty);
    });
  });
}

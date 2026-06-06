// test/intake_proposal_factory_shopping_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/intake_proposal_factory.dart';

void main() {
  group('IntakeProposalFactory.fromShoppingItems', () {
    test('parses "5 个" detail into quantity=5 unit=个', () {
      final items = [
        ShoppingItem(
          id: 'si1', name: '苹果', detail: '5 个',
          category: FoodCategories.other, isChecked: true,
        ),
      ];
      final proposals =
          IntakeProposalFactory.fromShoppingItems(items, const []);
      expect(proposals, hasLength(1));
      expect(proposals.first.quantity, '5');
      expect(proposals.first.unit, '个');
    });

    test('handles missing detail gracefully', () {
      final items = [
        ShoppingItem(
          id: 'si2', name: '葱', detail: '',
          category: FoodCategories.other, isChecked: true,
        ),
      ];
      final proposals =
          IntakeProposalFactory.fromShoppingItems(items, const []);
      expect(proposals.first.quantity, '1');
      expect(proposals.first.unit, '份');
    });

    test('origin=system and shelfLifeDays=null when no inventory match', () {
      final items = [
        ShoppingItem(
          id: 'si3', name: '盐', detail: '1 袋',
          category: FoodCategories.other, isChecked: true,
        ),
      ];
      final proposals =
          IntakeProposalFactory.fromShoppingItems(items, const []);
      expect(proposals.first.origin, FieldOrigin.system);
      expect(proposals.first.shelfLifeDays, isNull);
    });

    test('merge default action when inventory has matching non-perishable row',
        () {
      final inventory = [
        Ingredient(
          name: '米', quantity: '3', unit: 'kg', imageUrl: '',
          freshnessPercent: 1, state: FreshnessState.fresh,
          category: FoodCategories.other, storage: IconType.pantry,
        ),
      ];
      final items = [
        ShoppingItem(
          id: 'si4', name: '米', detail: '5 kg',
          category: FoodCategories.other, isChecked: true,
        ),
      ];
      final proposals = IntakeProposalFactory.fromShoppingItems(items, inventory);
      expect(proposals.first.action, IntakeAction.mergeInto);
    });
  });

  group('IntakeProposalFactory.isSinglePrefill', () {
    IntakeProposal proposal(IntakeAction action) => IntakeProposal(
          id: 'p',
          name: '番茄',
          quantity: '1',
          unit: '个',
          category: null,
          storage: IconType.fridge,
          shelfLifeDays: null,
          action: action,
        );

    test('empty list → false', () {
      expect(IntakeProposalFactory.isSinglePrefill(const []), isFalse);
    });

    test('single newRow → true (goes to prefill form)', () {
      expect(
        IntakeProposalFactory.isSinglePrefill([proposal(IntakeAction.newRow)]),
        isTrue,
      );
    });

    test('single mergeInto → false (must go through Review to merge)', () {
      expect(
        IntakeProposalFactory.isSinglePrefill([proposal(IntakeAction.mergeInto)]),
        isFalse,
      );
    });

    test('two proposals → false', () {
      expect(
        IntakeProposalFactory.isSinglePrefill(
          [proposal(IntakeAction.newRow), proposal(IntakeAction.newRow)],
        ),
        isFalse,
      );
    });
  });
}

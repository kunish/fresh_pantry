// lib/services/intake_proposal_factory.dart
import '../models/ingredient.dart';
import '../models/ingredient_draft.dart';
import '../models/proposal.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';
import 'proposal_planner.dart';

class IntakeProposalFactory {
  IntakeProposalFactory._();

  static List<IntakeProposal> fromDrafts(
    List<IngredientDraft> drafts,
    List<Ingredient> inventory,
  ) {
    return drafts.map((d) {
      final candidate = _Candidate(d);
      final defaultAction = ProposalPlanner.computeIntakeDefaultAction(
        candidate: candidate,
        inventory: inventory,
      );
      final i = defaultAction.targetIndex;
      return IntakeProposal(
        id: d.id,
        name: d.name.value,
        quantity: d.quantity.value,
        unit: d.unit.value,
        category: d.category.value,
        storage: d.storage.value ?? IconType.fridge,
        shelfLifeDays: d.shelfLifeDays.value,
        action: defaultAction.kind,
        mergeTargetId: i?.toString(),
        mergeTargetLabel: i == null
            ? null
            : '${inventory[i].name} ${inventory[i].quantity}${inventory[i].unit}',
      );
    }).toList();
  }

  static List<IntakeProposal> fromShoppingItems(
    List<ShoppingItem> items,
    List<Ingredient> inventory,
  ) {
    return items.map((item) {
      final (qty, unit) = _parseDetail(item.detail);
      // Inherit storage from a matching inventory row (name+unit) so the
      // planner's merge rule γ (name+unit+storage) can fire for non-perishables.
      final matchedStorage = _inferStorage(item.name, unit, inventory);
      final candidate = _ShoppingCandidate(
        name: item.name,
        unit: unit,
        storage: matchedStorage, // adopts inventory storage when match found
        category: item.category,
      );
      final defaultAction = ProposalPlanner.computeIntakeDefaultAction(
        candidate: candidate,
        inventory: inventory,
      );
      final i = defaultAction.targetIndex;
      return IntakeProposal(
        id: 'ix_${item.id}',
        name: item.name,
        quantity: qty,
        unit: unit,
        category: item.category,
        storage: matchedStorage,
        shelfLifeDays: null,
        action: defaultAction.kind,
        mergeTargetId: i?.toString(),
        mergeTargetLabel: i == null
            ? null
            : '${inventory[i].name} ${inventory[i].quantity}${inventory[i].unit}',
        origin: FieldOrigin.system,
      );
    }).toList();
  }

  static (String qty, String unit) _parseDetail(String detail) {
    final trimmed = detail.trim();
    if (trimmed.isEmpty) return ('1', '份');
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$').firstMatch(trimmed);
    if (m == null) return ('1', trimmed);
    return (m.group(1) ?? '1', (m.group(2) ?? '').trim().isEmpty
        ? '份'
        : (m.group(2) ?? '').trim());
  }

  /// Returns the storage of the first inventory row that matches name+unit,
  /// or [IconType.fridge] as the default when no match is found.
  static IconType _inferStorage(
    String name,
    String unit,
    List<Ingredient> inventory,
  ) {
    final lowerName = name.trim().toLowerCase();
    for (final row in inventory) {
      if (row.name.trim().toLowerCase() == lowerName &&
          row.unit.trim() == unit.trim()) {
        return row.storage;
      }
    }
    return IconType.fridge;
  }
}

class _Candidate implements IntakeCandidate {
  _Candidate(this.d);
  final IngredientDraft d;
  @override
  String get name => d.name.value;
  @override
  String get unit => d.unit.value;
  @override
  IconType get storage => d.storage.value ?? IconType.fridge;
  @override
  String? get category => d.category.value;
}

class _ShoppingCandidate implements IntakeCandidate {
  _ShoppingCandidate({
    required this.name,
    required this.unit,
    required this.storage,
    required this.category,
  });
  @override final String name;
  @override final String unit;
  @override final IconType storage;
  @override final String? category;
}

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
    return drafts
        .map(
          (d) => _build(
            id: d.id,
            name: d.name.value,
            quantity: d.quantity.value,
            unit: d.unit.value,
            category: d.category.value,
            storage: d.storage.value ?? IconType.fridge,
            shelfLifeDays: d.shelfLifeDays.value,
            inventory: inventory,
          ),
        )
        .toList();
  }

  static List<IntakeProposal> fromShoppingItems(
    List<ShoppingItem> items,
    List<Ingredient> inventory,
  ) {
    return items.map((item) {
      final (qty, unit) = _parseDetail(item.detail);
      // Inherit storage from a matching inventory row (name+unit) so the
      // planner's merge rule γ (name+unit+storage) can fire for non-perishables.
      final storage = _inferStorage(item.name, unit, inventory);
      return _build(
        id: 'ix_${item.id}',
        name: item.name,
        quantity: qty,
        unit: unit,
        category: item.category,
        storage: storage,
        shelfLifeDays: null,
        inventory: inventory,
        origin: FieldOrigin.system,
      );
    }).toList();
  }

  /// Builds one [IntakeProposal], resolving its default Intake action against
  /// the live inventory and capturing the merge-target hint + label. Shared by
  /// both intake sources so the proposal shape lives in one place.
  static IntakeProposal _build({
    required String id,
    required String name,
    required String quantity,
    required String unit,
    required String? category,
    required IconType storage,
    required int? shelfLifeDays,
    required List<Ingredient> inventory,
    FieldOrigin origin = FieldOrigin.ai,
  }) {
    final action = ProposalPlanner.computeIntakeDefaultAction(
      candidate: _Candidate(
        name: name,
        unit: unit,
        storage: storage,
        category: category,
      ),
      inventory: inventory,
    );
    final i = action.targetIndex;
    return IntakeProposal(
      id: id,
      name: name,
      quantity: quantity,
      unit: unit,
      category: category,
      storage: storage,
      shelfLifeDays: shelfLifeDays,
      action: action.kind,
      mergeTargetId: i?.toString(),
      mergeTargetLabel: i == null
          ? null
          : '${inventory[i].name} ${inventory[i].quantity}${inventory[i].unit}',
      origin: origin,
    );
  }

  static (String qty, String unit) _parseDetail(String detail) {
    final trimmed = detail.trim();
    if (trimmed.isEmpty) return ('1', '份');
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$').firstMatch(trimmed);
    if (m == null) return ('1', trimmed);
    return (
      m.group(1) ?? '1',
      (m.group(2) ?? '').trim().isEmpty ? '份' : (m.group(2) ?? '').trim(),
    );
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
  _Candidate({
    required this.name,
    required this.unit,
    required this.storage,
    required this.category,
  });
  @override
  final String name;
  @override
  final String unit;
  @override
  final IconType storage;
  @override
  final String? category;
}

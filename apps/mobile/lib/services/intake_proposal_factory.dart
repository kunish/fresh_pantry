// lib/services/intake_proposal_factory.dart
import '../models/ingredient.dart';
import '../models/ingredient_draft.dart';
import '../models/proposal.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';
import '../utils/quantity_text.dart';
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

  /// Whether a parsed batch should bypass the Review pipeline and go straight to
  /// the richer prefill add-form: exactly one proposal that is a brand-new row.
  ///
  /// A single proposal that would merge into an existing row must still go
  /// through Review so the merge actually happens — the append-only prefill form
  /// would otherwise create a duplicate row.
  static bool isSinglePrefill(List<IntakeProposal> proposals) =>
      proposals.length == 1 && proposals.first.action == IntakeAction.newRow;

  /// The Review-proposal id minted for a shopping-derived intake.
  ///
  /// The shopping flow uses this to tell which source rows actually applied, so
  /// the scheme has a single owner here instead of being re-built at the call
  /// site (which would silently break this cleanup if the scheme ever changed).
  static String proposalIdForShoppingItem(String itemId) => 'ix_$itemId';

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
        id: proposalIdForShoppingItem(item.id),
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
    final parsed = parseLeadingQuantity(trimmed);
    if (parsed == null) return ('1', trimmed);
    return (parsed.magnitude, parsed.remainder.isEmpty ? '份' : parsed.remainder);
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

import 'storage_area.dart';

enum IntakeAction { newRow, mergeInto }

enum DeductionAction { deduct, skip }

/// Source of a Proposal field's value — used by the Review UI to render origin
/// dots and to know whether the user has touched a value.
enum FieldOrigin { ai, system, user }

sealed class Proposal {
  Proposal({required this.id, this.selected = true});
  final String id;
  final bool selected;
}

class IntakeProposal extends Proposal {
  IntakeProposal({
    required super.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.storage,
    required this.shelfLifeDays,
    this.action = IntakeAction.newRow,
    this.mergeTargetId,
    this.mergeTargetLabel,
    this.origin = FieldOrigin.ai,
    this.userEdited = false,
    super.selected,
  });

  final String name;
  final String quantity;
  final String unit;
  final String? category;
  final IconType storage;
  final int? shelfLifeDays;

  final IntakeAction action;

  /// Set when [action] == [IntakeAction.mergeInto]; references the inventory
  /// row to merge into. `mergeTargetId` corresponds to the inventory list index
  /// at the time the Proposal was computed (callers must re-resolve before
  /// applying to defend against list reordering).
  final String? mergeTargetId;
  final String? mergeTargetLabel;

  /// Origin of the data before user edits; set to [FieldOrigin.ai] for AI
  /// parses, [FieldOrigin.system] for shopping-derived proposals.
  final FieldOrigin origin;

  /// True after the user touches any field in the Review screen.
  final bool userEdited;

  IntakeProposal copyWith({
    String? name,
    String? quantity,
    String? unit,
    String? category,
    IconType? storage,
    int? shelfLifeDays,
    IntakeAction? action,
    String? mergeTargetId,
    String? mergeTargetLabel,
    bool? selected,
    bool? userEdited,
  }) {
    return IntakeProposal(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      storage: storage ?? this.storage,
      shelfLifeDays: shelfLifeDays ?? this.shelfLifeDays,
      action: action ?? this.action,
      mergeTargetId: mergeTargetId ?? this.mergeTargetId,
      mergeTargetLabel: mergeTargetLabel ?? this.mergeTargetLabel,
      origin: origin,
      userEdited: userEdited ?? this.userEdited,
      selected: selected ?? this.selected,
    );
  }
}

class DeductionCandidate {
  const DeductionCandidate({
    required this.inventoryRowIndex,
    required this.displayLabel,
  });
  final int inventoryRowIndex;
  final String displayLabel;
}

class DeductionProposal extends Proposal {
  DeductionProposal({
    required super.id,
    required this.recipeIngredientName,
    required this.requiredQty,
    required this.candidates,
    required this.chosenIndex,
    required this.deductAmount,
    this.action = DeductionAction.deduct,
    super.selected,
  });

  factory DeductionProposal.empty({
    required String id,
    required String recipeIngredientName,
    required String requiredQty,
  }) =>
      DeductionProposal(
        id: id,
        recipeIngredientName: recipeIngredientName,
        requiredQty: requiredQty,
        candidates: const [],
        chosenIndex: -1,
        deductAmount: '0',
        action: DeductionAction.skip,
        selected: false,
      );

  final String recipeIngredientName;
  final String requiredQty;
  final List<DeductionCandidate> candidates;

  /// The currently chosen inventory row's index. -1 when [action]=skip.
  final int chosenIndex;

  /// Quantity to deduct, as a string (matches `Ingredient.quantity` shape).
  final String deductAmount;

  final DeductionAction action;

  DeductionProposal copyWith({
    int? chosenIndex,
    String? deductAmount,
    DeductionAction? action,
    bool? selected,
  }) {
    return DeductionProposal(
      id: id,
      recipeIngredientName: recipeIngredientName,
      requiredQty: requiredQty,
      candidates: candidates,
      chosenIndex: chosenIndex ?? this.chosenIndex,
      deductAmount: deductAmount ?? this.deductAmount,
      action: action ?? this.action,
      selected: selected ?? this.selected,
    );
  }
}

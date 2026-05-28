import '../models/ingredient.dart';
import '../models/proposal.dart';
import '../models/recipe.dart';
import 'proposal_planner.dart';

class DeductionProposalFactory {
  DeductionProposalFactory._();

  /// Converts a cooked recipe into reviewable inventory deductions.
  ///
  /// [ProposalPlanner] owns fuzzy inventory matching; this factory owns the
  /// recipe-completion adapter shape so recipe flows do not construct
  /// DeductionProposal rows inline.
  static List<DeductionProposal> forRecipe(
    Recipe recipe,
    List<Ingredient> inventory,
  ) {
    final list = <DeductionProposal>[];
    for (var i = 0; i < recipe.ingredients.length; i++) {
      final ri = recipe.ingredients[i];
      final candidates = ProposalPlanner.fuzzyMatchInventoryRows(
        ri.name,
        inventory,
      );
      if (candidates.isEmpty) {
        list.add(
          DeductionProposal.empty(
            id: 'd_${recipe.id}_$i',
            recipeIngredientName: ri.name,
            requiredQty: ri.amount,
          ),
        );
      } else {
        list.add(
          DeductionProposal(
            id: 'd_${recipe.id}_$i',
            recipeIngredientName: ri.name,
            requiredQty: ri.amount,
            candidates: candidates,
            chosenIndex: candidates.first.inventoryRowIndex,
            deductAmount: _initialDeductAmount(ri, candidates.first),
          ),
        );
      }
    }
    return list;
  }

  /// Picks the default deduct amount for a matched recipe ingredient.
  ///
  /// Uses the recipe's real numeric magnitude only when it can be reconciled
  /// with the chosen inventory row's unit; otherwise falls back to 1 (a safe
  /// "used one" default) instead of blindly deducting the raw recipe number
  /// against a different unit. Always returns a parseable number so the Review
  /// stepper stays usable and a deduction can never silently apply zero.
  static String _initialDeductAmount(
    RecipeIngredient ri,
    DeductionCandidate chosen,
  ) {
    final (magnitude, recipeUnit) = _parseMagnitudeUnit(ri);
    if (magnitude == null || magnitude <= 0) return '1';
    final rowUnit = chosen.inventoryRowUnit.trim();
    final unitsCompatible =
        recipeUnit.isEmpty || rowUnit.isEmpty || recipeUnit == rowUnit;
    if (!unitsCompatible) return '1';
    return _formatNumber(magnitude);
  }

  static (double?, String) _parseMagnitudeUnit(RecipeIngredient ri) {
    final structured = double.tryParse(ri.quantity.trim());
    if (structured != null) return (structured, ri.unit.trim());
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(.*)$',
    ).firstMatch(ri.amount.trim());
    if (match == null) return (null, ri.unit.trim());
    final magnitude = double.tryParse(match.group(1) ?? '');
    final parsedUnit = (match.group(2) ?? '').trim();
    return (magnitude, parsedUnit.isEmpty ? ri.unit.trim() : parsedUnit);
  }

  static String _formatNumber(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proposal.dart';
import '../models/shopping_item.dart';
import '../services/intake_proposal_factory.dart';
import 'inventory_provider.dart';
import 'shopping_provider.dart';

/// ViewModel-level seam for the shopping → intake-review flow (mirrors
/// [BackupController]).
///
/// It owns the data orchestration — build proposals against live inventory, and
/// clear the source rows whose proposal actually applied — so the rules are
/// testable without pumping a widget and the `ix_` proposal-id scheme never
/// leaks into the screen. The View keeps every UI concern: seeding the review
/// notifier, navigation, `context.mounted` guards and snackbars.
class ShoppingIntakeController {
  ShoppingIntakeController(this._ref);

  final Ref _ref;

  /// Builds intake proposals for [items] against the live inventory.
  List<IntakeProposal> buildProposals(List<ShoppingItem> items) {
    final inventory = _ref.read(inventoryProvider);
    return IntakeProposalFactory.fromShoppingItems(items, inventory);
  }

  /// Removes each [source] row whose intake proposal is present in [appliedIds].
  ///
  /// Sequential + per-item try/catch on purpose: a row that entered inventory
  /// but fails to clear from the list stays so a later attempt can retry the
  /// removal, and a cancelled / deselected proposal (absent from [appliedIds])
  /// is never silently discarded.
  Future<void> removeApplied(
    List<ShoppingItem> source,
    Set<String> appliedIds,
  ) async {
    if (appliedIds.isEmpty) return;
    final shopping = _ref.read(shoppingProvider.notifier);
    for (final item in source) {
      if (!appliedIds.contains(
        IntakeProposalFactory.proposalIdForShoppingItem(item.id),
      )) {
        continue;
      }
      try {
        await shopping.remove(item.id);
      } catch (_) {
        // Entered inventory but couldn't be cleared from the list; leave it so
        // a later attempt can retry the removal.
      }
    }
  }
}

final shoppingIntakeControllerProvider = Provider<ShoppingIntakeController>(
  (ref) => ShoppingIntakeController(ref),
);

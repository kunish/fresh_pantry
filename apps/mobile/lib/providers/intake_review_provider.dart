import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient_identity.dart';
import '../models/proposal.dart';
import '../storage/intake_review_draft_repo.dart';
import 'inventory_provider.dart';
import 'review_notifier_base.dart';
import 'storage_service_provider.dart';

const intakeReviewDraftKey = IntakeReviewDraftRepo.storageKey;

@immutable
class IntakeReviewState {
  const IntakeReviewState({this.proposals = const [], this.persistError});

  final List<IntakeProposal> proposals;
  final Object? persistError;

  IntakeReviewState copyWith({
    List<IntakeProposal>? proposals,
    Object? persistError,
    bool clearPersistError = false,
  }) => IntakeReviewState(
    proposals: proposals ?? this.proposals,
    persistError: clearPersistError ? null : persistError ?? this.persistError,
  );

  int get selectedCount => proposals.where((p) => p.selected).length;
}

class IntakeReviewNotifier extends Notifier<IntakeReviewState>
    with ReviewNotifierBase<IntakeReviewState> {
  late IntakeReviewDraftRepo _repo;

  @override
  IntakeReviewState build() {
    _repo = ref.read(intakeReviewDraftRepoProvider);
    return IntakeReviewState(proposals: _repo.load());
  }

  void seed(List<IntakeProposal> proposals) {
    state = IntakeReviewState(proposals: proposals);
    _schedulePersistDraft();
  }

  @override
  void clear() {
    state = const IntakeReviewState();
    _schedulePersistDraft();
  }

  void toggleSelected(String id) {
    state = state.copyWith(
      proposals:
          state.proposals
              .map((p) => p.id == id ? p.copyWith(selected: !p.selected) : p)
              .toList(),
      clearPersistError: true,
    );
    _schedulePersistDraft();
  }

  void toggleAction(String id) {
    state = state.copyWith(
      proposals:
          state.proposals.map((p) {
            if (p.id != id) return p;
            if (p.mergeTargetId == null) {
              return p; // no merge target -> can't toggle
            }
            // Perishables always create a new Batch; never let the user toggle
            // one into a merge.
            if (p.action == IntakeAction.newRow &&
                IngredientIdentity.isPerishable(
                  category: p.category,
                  name: p.name,
                )) {
              return p;
            }
            final next =
                p.action == IntakeAction.newRow
                    ? IntakeAction.mergeInto
                    : IntakeAction.newRow;
            return p.copyWith(action: next, userEdited: true);
          }).toList(),
      clearPersistError: true,
    );
    _schedulePersistDraft();
  }

  void updateProposal(IntakeProposal updated) {
    final coerced = _coerceActionForRules(updated);
    state = state.copyWith(
      proposals:
          state.proposals.map((p) => p.id == coerced.id ? coerced : p).toList(),
      clearPersistError: true,
    );
    _schedulePersistDraft();
  }

  /// Keeps the Review action consistent with the domain rule after an edit:
  /// if a change makes the proposal Perishable, drop any stale `mergeInto` so
  /// the UI reflects that perishables always create a new Batch.
  IntakeProposal _coerceActionForRules(IntakeProposal p) {
    if (p.action == IntakeAction.mergeInto &&
        IngredientIdentity.isPerishable(category: p.category, name: p.name)) {
      return p.copyWith(action: IntakeAction.newRow);
    }
    return p;
  }

  void toggleSelectAll() {
    final allSelected = state.proposals.every((p) => p.selected);
    state = state.copyWith(
      proposals:
          state.proposals
              .map((p) => p.copyWith(selected: !allSelected))
              .toList(),
      clearPersistError: true,
    );
    _schedulePersistDraft();
  }

  /// Applies the reviewed proposals and returns the ids of the proposals that
  /// were actually applied, so the caller can clean up only those source rows.
  Future<Set<String>> applyToInventory(InventoryNotifier inventory) async {
    return applyAndClear(() => inventory.applyIntakeProposals(state.proposals));
  }

  void _schedulePersistDraft() {
    unawaited(
      _persistDraft()
          .then((_) {
            if (state.persistError != null) {
              state = state.copyWith(clearPersistError: true);
            }
          })
          .catchError((Object error) {
            state = state.copyWith(persistError: error);
          }),
    );
  }

  Future<void> _persistDraft() => _repo.save(state.proposals);
}

final intakeReviewProvider =
    NotifierProvider<IntakeReviewNotifier, IntakeReviewState>(
      IntakeReviewNotifier.new,
    );

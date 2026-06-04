import 'dart:convert';

import '../models/proposal.dart';
import '../models/storage_area.dart';
import 'storage_adapter.dart';

/// Persists the in-progress Intake Review draft (a list of [IntakeProposal]) as
/// a JSON array, owning the proposal⇄JSON codec.
///
/// Mirrors the [AiSettingsRepo] / [FavoriteRecipesRepo] seam over a
/// [StorageAdapter]; a missing or malformed blob yields an empty draft. An
/// empty draft removes the key so a stale draft never lingers across launches.
class IntakeReviewDraftRepo {
  static const storageKey = 'intake_review_draft';

  final StorageAdapter _adapter;

  IntakeReviewDraftRepo(this._adapter);

  List<IntakeProposal> load() {
    final raw = _adapter.read(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(_fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<IntakeProposal> proposals) {
    if (proposals.isEmpty) return _adapter.remove(storageKey);
    return _adapter.write(
      storageKey,
      jsonEncode(proposals.map(_toJson).toList()),
    );
  }

  Map<String, dynamic> _toJson(IntakeProposal p) => {
    'id': p.id,
    'name': p.name,
    'quantity': p.quantity,
    'unit': p.unit,
    'category': p.category,
    'storage': p.storage.name,
    'shelfLifeDays': p.shelfLifeDays,
    'action': p.action.name,
    'mergeTargetId': p.mergeTargetId,
    'mergeTargetLabel': p.mergeTargetLabel,
    'origin': p.origin.name,
    'userEdited': p.userEdited,
    'selected': p.selected,
  };

  IntakeProposal _fromJson(Map<String, dynamic> j) => IntakeProposal(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    quantity: j['quantity'] as String? ?? '1',
    unit: j['unit'] as String? ?? '个',
    category: j['category'] as String?,
    storage: iconTypeFromName(j['storage'] as String?),
    shelfLifeDays: (j['shelfLifeDays'] as num?)?.toInt(),
    action: IntakeAction.values.byName(
      (j['action'] as String?) ?? IntakeAction.newRow.name,
    ),
    mergeTargetId: j['mergeTargetId'] as String?,
    mergeTargetLabel: j['mergeTargetLabel'] as String?,
    origin: FieldOrigin.values.byName(
      (j['origin'] as String?) ?? FieldOrigin.ai.name,
    ),
    userEdited: j['userEdited'] as bool? ?? false,
    selected: j['selected'] as bool? ?? true,
  );
}

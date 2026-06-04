import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'household_content_sync_coordinator.dart';
import 'sync_providers.dart';

/// Lifecycle glue for household content sync: watches the selected household
/// and drives a [HouseholdContentSyncCoordinator], which owns all the actual
/// upload / subscribe / merge work. Kept as a thin widget so the sync
/// orchestration has a single, testable owner outside the widget tree.
class HouseholdContentSync extends ConsumerStatefulWidget {
  const HouseholdContentSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HouseholdContentSync> createState() =>
      _HouseholdContentSyncState();
}

class _HouseholdContentSyncState extends ConsumerState<HouseholdContentSync> {
  late final HouseholdContentSyncCoordinator _coordinator =
      HouseholdContentSyncCoordinator(ref);

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(selectedHouseholdIdProvider).trim();
    _coordinator.syncTo(householdId);
    return widget.child;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Currently selected tab index (0-3)
final navigationProvider = StateProvider<int>((ref) => 0);

/// Whether search overlay is active
final searchActiveProvider = StateProvider<bool>((ref) => false);

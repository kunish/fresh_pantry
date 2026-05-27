import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/backend_config.dart';

final backendConfigProvider = Provider<BackendConfig>((ref) {
  return BackendConfig.fromEnvironment();
});

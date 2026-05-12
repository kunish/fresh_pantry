import 'package:flutter/material.dart';

import 'fk_pill.dart';

/// 食材新鲜度状态徽章 — 设计稿 `ui.jsx::FKStatusBadge`。
class FkStatusBadge extends StatelessWidget {
  final FkStatus status;
  final bool sm;

  const FkStatusBadge({super.key, required this.status, this.sm = false});

  @override
  Widget build(BuildContext context) => FkPill.status(status, sm: sm);
}

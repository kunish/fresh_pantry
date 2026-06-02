import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// 项目内统一的确认对话框。返回 `true` 表示用户确认,`false` / `null` 表示取消。
///
/// 视觉对齐既有 `AlertDialog` 实现:`AppColors.surface` 背景、20 圆角、
/// PlusJakartaSans 标题、Manrope 内文 + 取消/确认按钮。
/// `isDestructive=true` 时确认按钮使用 `AppColors.error` 红字加粗。
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
      content: Text(
        content,
        style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            cancelLabel,
            style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: GoogleFonts.manrope(
              color: isDestructive ? AppColors.error : AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 单按钮信息提示对话框。视觉与 [showAppConfirmDialog] 对齐:`AppColors.surface`
/// 背景、`AppRadius.xl` 圆角、PlusJakartaSans 标题、Manrope 内文。
Future<void> showAppInfoDialog(
  BuildContext context, {
  required String title,
  required String content,
  String buttonLabel = '好',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
      content: Text(
        content,
        style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            buttonLabel,
            style: GoogleFonts.manrope(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

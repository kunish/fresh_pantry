import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

Future<DateTimeRange?> showExpiryRangePicker({
  required BuildContext context,
  required DateTimeRange initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
  required DateTime currentDate,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    useSafeArea: false,
    barrierColor: AppColors.modalBarrier,
    builder:
        (context) => Localizations.override(
          context: context,
          locale: const Locale('zh', 'CN'),
          child: ExpiryRangePickerDialog(
            initialDateRange: initialDateRange,
            firstDate: firstDate,
            lastDate: lastDate,
            currentDate: currentDate,
          ),
        ),
  );
}

class ExpiryRangePickerDialog extends StatefulWidget {
  const ExpiryRangePickerDialog({
    super.key,
    required this.initialDateRange,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
  });

  final DateTimeRange initialDateRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;

  @override
  State<ExpiryRangePickerDialog> createState() =>
      _ExpiryRangePickerDialogState();
}

class _ExpiryRangePickerDialogState extends State<ExpiryRangePickerDialog> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _editingStartDate = true;

  SystemUiOverlayStyle get _overlayStyle {
    return SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: AppColors.surface,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
    );
  }

  DateTime get _firstDate => DateUtils.dateOnly(widget.firstDate);
  DateTime get _lastDate => DateUtils.dateOnly(widget.lastDate);
  DateTime get _activeDate => _editingStartDate ? _startDate : _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = _clampDate(
      DateUtils.dateOnly(widget.initialDateRange.start),
      _firstDate,
      _lastDate,
    );
    _endDate = _clampDate(
      DateUtils.dateOnly(widget.initialDateRange.end),
      _startDate,
      _lastDate,
    );
  }

  DateTime _clampDate(DateTime date, DateTime minimum, DateTime maximum) {
    if (date.isBefore(minimum)) return minimum;
    if (date.isAfter(maximum)) return maximum;
    return date;
  }

  void _setActiveDate(DateTime date) {
    final selected = _clampDate(
      DateUtils.dateOnly(date),
      _firstDate,
      _lastDate,
    );
    setState(() {
      if (_editingStartDate) {
        _startDate = selected;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = selected;
        if (_startDate.isAfter(_endDate)) {
          _startDate = _endDate;
        }
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop(DateTimeRange(start: _startDate, end: _endDate));
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('expiry-range-picker'),
      color: AppColors.surface,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _overlayStyle,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(),
              _buildHeader(),
              _buildRangeTabs(),
              const SizedBox(height: AppSpacing.xl),
              Expanded(child: _buildDateWheel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            color: AppColors.onSurfaceVariant,
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          TextButton(
            onPressed: _confirm,
            child: Text(
              '确定',
              style: GoogleFonts.manrope(
                color: AppColors.primary,
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, AppSpacing.xs, AppSpacing.xxxl, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择保质期范围',
            style: GoogleFonts.manrope(
              color: AppColors.onSurfaceVariant,
              fontSize: AppFontSize.lg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildRangeTab(
                key: const Key('expiry-start-date-tab'),
                label: '起始日期',
                date: _startDate,
                selected: _editingStartDate,
                onTap: () => setState(() => _editingStartDate = true),
              ),
            ),
            Expanded(
              child: _buildRangeTab(
                key: const Key('expiry-end-date-tab'),
                label: '结束日期',
                date: _endDate,
                selected: !_editingStartDate,
                onTap: () => setState(() => _editingStartDate = false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeTab({
    required Key key,
    required String label,
    required DateTime date,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.surfaceContainerLowest : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: AppColors.subtleShadow,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                  : null,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.manrope(
                color:
                    selected ? AppColors.primary : AppColors.onSurfaceVariant,
                fontSize: AppFontSize.sm,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _formatDate(date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                color: AppColors.onSurface,
                fontSize: AppFontSize.sm,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateWheel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.xxl),
      child: CupertinoTheme(
        data: CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: AppColors.primary,
          scaffoldBackgroundColor: AppColors.surface,
          textTheme: CupertinoTextThemeData(
            dateTimePickerTextStyle: GoogleFonts.manrope(
              color: AppColors.onSurface,
              fontSize: AppFontSize.xxl,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        child: KeyedSubtree(
          key: const Key('expiry-date-wheel'),
          child: CupertinoDatePicker(
            key: ValueKey(
              'expiry-date-wheel-${_editingStartDate ? 'start' : 'end'}',
            ),
            mode: CupertinoDatePickerMode.date,
            initialDateTime: _activeDate,
            minimumYear: _firstDate.year,
            maximumYear: _lastDate.year,
            dateOrder: DatePickerDateOrder.ymd,
            onDateTimeChanged: _setActiveDate,
          ),
        ),
      ),
    );
  }
}

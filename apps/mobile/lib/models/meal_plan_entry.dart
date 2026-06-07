import 'sync_metadata.dart';

/// 周膳食计划的一条记录:某一天计划做的一道菜。
///
/// 设计取舍:
/// - **一条记录 = 一道菜**(而非「一天一行」)。与库存/购物的列表实体模式一致,
///   增删与同步粒度更细;两位家庭成员往同一天各加一道菜时不会互相覆盖。
/// - 菜名/封面做**冗余快照**([recipeName] / [recipeImageUrl]),日历无需解析
///   菜谱即可渲染,且原菜谱被删除/改名后历史计划仍可正常展示。[recipeId] 仍保留,
///   供「查看详情」「完成扣减」回溯到原菜谱(预置库或自定义)。
/// - [date] 一律归一化到**本地日期(零点)**,只保留年月日:计划「6 月 8 日做某菜」
///   不应因设备时区漂移成 6 月 7/9 日。
class MealPlanEntry {
  final String id;

  /// 计划日期,已归一化到本地零点(只取年月日)。
  final DateTime date;

  /// 关联菜谱 id(预置库或自定义菜谱)。
  final String recipeId;

  /// 菜名快照(冗余,见类注释)。
  final String recipeName;

  /// 封面快照(冗余),可空。
  final String? recipeImageUrl;

  /// 份数,默认 1。供后续按份数缩放「缺料」计算用。
  final int servings;

  /// 是否已完成(做过这道菜)。
  final bool done;

  final int remoteVersion;
  final DateTime? clientUpdatedAt;
  final DateTime? deletedAt;

  SyncMetadata get syncMetadata => SyncMetadata(
    remoteVersion: remoteVersion,
    clientUpdatedAt: clientUpdatedAt,
    deletedAt: deletedAt,
  );

  MealPlanEntry({
    required this.id,
    required DateTime date,
    required this.recipeId,
    required this.recipeName,
    this.recipeImageUrl,
    this.servings = 1,
    this.done = false,
    this.remoteVersion = 0,
    this.clientUpdatedAt,
    this.deletedAt,
  }) : date = dateOnly(date);

  /// 把任意 [DateTime] 截到本地零点(只留年月日),供日期归一化与按天分组。
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// 稳定的日期键 `yyyy-MM-dd`,用于按天分组与 JSON 序列化(避免时区漂移)。
  static String dateKey(DateTime value) {
    final d = dateOnly(value);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MealPlanEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  MealPlanEntry copyWith({
    String? id,
    DateTime? date,
    String? recipeId,
    String? recipeName,
    String? recipeImageUrl,
    int? servings,
    bool? done,
    int? remoteVersion,
    DateTime? clientUpdatedAt,
    DateTime? deletedAt,
    bool clearClientUpdatedAt = false,
    bool clearDeletedAt = false,
  }) {
    return MealPlanEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      recipeId: recipeId ?? this.recipeId,
      recipeName: recipeName ?? this.recipeName,
      recipeImageUrl: recipeImageUrl ?? this.recipeImageUrl,
      servings: servings ?? this.servings,
      done: done ?? this.done,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      clientUpdatedAt: clearClientUpdatedAt
          ? null
          : clientUpdatedAt ?? this.clientUpdatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': dateKey(date),
      'recipeId': recipeId,
      'recipeName': recipeName,
      'recipeImageUrl': recipeImageUrl,
      'servings': servings,
      'done': done,
      'remoteVersion': remoteVersion,
      'clientUpdatedAt': dateTimeToJsonValue(clientUpdatedAt),
      'deletedAt': dateTimeToJsonValue(deletedAt),
    };
  }

  /// 从 JSON 还原。日期缺失/无法解析视为脏数据 → 抛 [FormatException],
  /// 由仓储层 try/catch 跳过该行(与 [CustomRecipeRepo] 一致),不做静默兜底。
  factory MealPlanEntry.fromJson(Map<String, dynamic> json) {
    final date = _parseDate(json['date']);
    if (date == null) {
      throw const FormatException('MealPlanEntry.date missing or unparseable');
    }
    return MealPlanEntry(
      id: json['id'] as String? ?? '',
      date: date,
      recipeId: json['recipeId'] as String? ?? '',
      recipeName: json['recipeName'] as String? ?? '',
      recipeImageUrl: json['recipeImageUrl'] as String?,
      servings: (json['servings'] as num?)?.toInt() ?? 1,
      done: json['done'] as bool? ?? false,
      remoteVersion: (json['remoteVersion'] as num?)?.toInt() ?? 0,
      clientUpdatedAt: dateTimeFromJsonValue(json['clientUpdatedAt']),
      deletedAt: dateTimeFromJsonValue(json['deletedAt']),
    );
  }

  /// 解析 `yyyy-MM-dd` 键,兼容历史可能写入的完整 ISO 字符串;均归一化到本地零点。
  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value.trim());
    return parsed == null ? null : dateOnly(parsed);
  }
}

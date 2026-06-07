import '../data/food_categories.dart';
import 'sync_metadata.dart';

/// 一条食材离库记录:某样食材在某时刻「吃完/用掉」还是「浪费扔掉」。
///
/// 这是减废成效统计的**真值来源**——库存只记录当前持有,离库的去向(消耗 vs 浪费)
/// 过去没有任何留存。一条记录 = 一次离库事件,append-only(不编辑历史)。
///
/// 设计取舍:
/// - 名称/分类做**快照**([name] / [category]):统计无需回查库存(物品早已删除),
///   且支持分类级洞察(「哪类食材最常被浪费」)。
/// - [outcome] 是核心信号,由删除时的轻量追问 / 做菜扣减(自动消耗)写入。
/// - [wasExpiring] 记录离库时是否已临期/过期:支撑「抢救临期 N 样」(消耗且临期)与
///   「新鲜即弃」(浪费且未临期,最可惜的浪费)两个洞察。
/// - [loggedAt] 存完整时间戳(UTC),统计按需 `.toLocal()` 归到本地日/周/月。
/// - 数量不入账:库存数量是自由文本(「1」「半」「500」),跨单位求和无意义;
///   MVP 以**件数**口径,诚实且可达。
class FoodLogEntry {
  final String id;

  /// 食材名快照(冗余,见类注释)。
  final String name;

  /// 分类快照,用于分类级减废洞察。
  final String category;

  /// 这次离库是消耗还是浪费。
  final FoodLogOutcome outcome;

  /// 事件时间(完整时间戳)。构造时归一化到 UTC,统计再转本地分组。
  final DateTime loggedAt;

  /// 离库时是否已临期/过期(fresh 之外的状态)。
  final bool wasExpiring;

  final int remoteVersion;
  final DateTime? clientUpdatedAt;
  final DateTime? deletedAt;

  SyncMetadata get syncMetadata => SyncMetadata(
    remoteVersion: remoteVersion,
    clientUpdatedAt: clientUpdatedAt,
    deletedAt: deletedAt,
  );

  FoodLogEntry({
    required this.id,
    required this.name,
    this.category = FoodCategories.other,
    required this.outcome,
    required DateTime loggedAt,
    this.wasExpiring = false,
    this.remoteVersion = 0,
    this.clientUpdatedAt,
    this.deletedAt,
  }) : loggedAt = loggedAt.toUtc();

  /// 生成规范格式的离库记录 id(`fl_<ms>`),与库存/购物的 id 约定一致。
  static String newId() => 'fl_${DateTime.now().millisecondsSinceEpoch}';

  bool get isConsumed => outcome == FoodLogOutcome.consumed;
  bool get isWasted => outcome == FoodLogOutcome.wasted;

  /// 抢救临期:消耗了一样已临期/过期的食材(正向减废成效)。
  bool get rescuedExpiring => isConsumed && wasExpiring;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoodLogEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  FoodLogEntry copyWith({
    String? id,
    String? name,
    String? category,
    FoodLogOutcome? outcome,
    DateTime? loggedAt,
    bool? wasExpiring,
    int? remoteVersion,
    DateTime? clientUpdatedAt,
    DateTime? deletedAt,
    bool clearClientUpdatedAt = false,
    bool clearDeletedAt = false,
  }) {
    return FoodLogEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      outcome: outcome ?? this.outcome,
      loggedAt: loggedAt ?? this.loggedAt,
      wasExpiring: wasExpiring ?? this.wasExpiring,
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
      'name': name,
      'category': category,
      'outcome': outcome.name,
      'loggedAt': loggedAt.toIso8601String(),
      'wasExpiring': wasExpiring,
      'remoteVersion': remoteVersion,
      'clientUpdatedAt': dateTimeToJsonValue(clientUpdatedAt),
      'deletedAt': dateTimeToJsonValue(deletedAt),
    };
  }

  /// 从 JSON 还原。时间缺失/无法解析视为脏数据 → 抛 [FormatException],
  /// 由仓储层 try/catch 跳过该行(与 [MealPlanEntry] 一致),不做静默兜底。
  factory FoodLogEntry.fromJson(Map<String, dynamic> json) {
    final loggedAt = dateTimeFromJsonValue(json['loggedAt']);
    if (loggedAt == null) {
      throw const FormatException(
        'FoodLogEntry.loggedAt missing or unparseable',
      );
    }
    return FoodLogEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? FoodCategories.other,
      outcome: FoodLogOutcome.fromName(json['outcome'] as String?),
      loggedAt: loggedAt,
      wasExpiring: json['wasExpiring'] as bool? ?? false,
      remoteVersion: (json['remoteVersion'] as num?)?.toInt() ?? 0,
      clientUpdatedAt: dateTimeFromJsonValue(json['clientUpdatedAt']),
      deletedAt: dateTimeFromJsonValue(json['deletedAt']),
    );
  }
}

/// 离库去向。未知/历史脏数据回落到 [consumed](保守:不夸大浪费量)。
enum FoodLogOutcome {
  consumed,
  wasted;

  static FoodLogOutcome fromName(String? name) {
    for (final o in FoodLogOutcome.values) {
      if (o.name == name) return o;
    }
    return FoodLogOutcome.consumed;
  }
}

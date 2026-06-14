import SwiftUI

/// Per-100g macro nutrition card, shown only when Open Food Facts supplied at
/// least one macro (`NutritionFacts.hasAny`). Ported from the Flutter
/// `_NutritionCard`: header "营养成分 · 每 100g", a row of 热量/蛋白质/碳水/脂肪
/// stat columns (only the non-nil fields), value formatting whole→int else
/// 1-decimal.
struct NutritionCard: View {
    let nutrition: NutritionFacts
    /// 副标题语义:库存食材是「每 100g」(OFF 默认),菜谱是「每份 · 约」(估算)。
    var caption: String = "每 100g"

    var body: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                Text("营养成分 · \(caption)")
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                HStack(alignment: .top, spacing: FkSpacing.md) {
                    ForEach(columns, id: \.label) { column in
                        statColumn(label: column.label, value: column.value, unit: column.unit)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private struct Column {
        let label: String
        let value: String
        let unit: String
    }

    private var columns: [Column] {
        var result: [Column] = []
        if let energyKcal = nutrition.energyKcal {
            result.append(Column(label: "热量", value: Self.format(energyKcal), unit: "kcal"))
        }
        if let protein = nutrition.protein {
            result.append(Column(label: "蛋白质", value: Self.format(protein), unit: "g"))
        }
        if let carbs = nutrition.carbs {
            result.append(Column(label: "碳水", value: Self.format(carbs), unit: "g"))
        }
        if let fat = nutrition.fat {
            result.append(Column(label: "脂肪", value: Self.format(fat), unit: "g"))
        }
        return result
    }

    private func statColumn(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: FkSpacing.xs) {
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            HStack(alignment: .firstTextBaseline, spacing: FkSpacing.xs) {
                Text(value)
                    .font(.fkHeroSubStat)
                    .foregroundStyle(Color.fkOnSurface)
                Text(unit)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }

    /// whole → int string, else 1-decimal. Matches the Flutter `_NutritionCard._fmt`
    /// (`toStringAsFixed(1)`), distinct from the 2-decimal `QuantityText`.
    static func format(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

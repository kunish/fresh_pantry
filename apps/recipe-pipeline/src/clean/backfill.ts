import { normalizeIngredient } from './normalize';
import type { CleanRecipe, Ingredient } from './schema';

/**
 * 把「校验后的用量修正」回填到清洗后菜谱里仍缺量的食材。
 *
 * 背景:HowToCook 源把部分食材的明确用量只写在「## 操作」步骤里(如「撒 5g 生粉」),
 * 而清洗管线早期只从「## 计算」总量段抽量,导致这些食材落成「只有 name」。本模块消费
 * 多代理从步骤里找回并对抗校验过的用量(kind="amount"),其余源里压根没写数字的食材
 * (kind="fuzzy" 或无匹配)统一落「适量」note——只回填、绝不编造数字。
 *
 * 纯函数:不改入参,已带 quantity 的食材原样不动。数字字段语义(quantityMax>quantity、
 * 空 unit 省略)统一交给 normalizeIngredient 兜底,与管线其余路径一致。
 */

export type CorrectionKind = 'amount' | 'fuzzy';

export interface Correction {
  name: string;
  kind: CorrectionKind;
  quantity?: number;
  quantityMax?: number;
  unit?: string;
}

export interface RecipeCorrections {
  id: string;
  corrections: Correction[];
}

export interface BackfillReport {
  /** 从源步骤找回真实数字、成功回填 quantity 的食材数。 */
  amountsApplied: number;
  /** 源里无明确数字、落「适量」note(或保留已有模糊 note)的食材数。 */
  fuzzyMarked: number;
  /** 本就有 quantity、原样未动的食材数。 */
  alreadyQuantified: number;
  /** 指向「不存在或已带量」食材、未被采用的修正条目数。 */
  unmatched: number;
}

const FUZZY_NOTE = '适量';

export function applyBackfill(
  recipes: CleanRecipe[],
  corrections: RecipeCorrections[],
): { recipes: CleanRecipe[]; report: BackfillReport } {
  const byId = new Map<string, Map<string, Correction>>();
  for (const rc of corrections) {
    const m = byId.get(rc.id) ?? new Map<string, Correction>();
    for (const c of rc.corrections) m.set(c.name, c);
    byId.set(rc.id, m);
  }

  const report: BackfillReport = {
    amountsApplied: 0, fuzzyMarked: 0, alreadyQuantified: 0, unmatched: 0,
  };
  const usedByRecipe = new Map<string, Set<string>>();

  const out = recipes.map((r) => {
    const corr = byId.get(r.id);
    const used = new Set<string>();
    usedByRecipe.set(r.id, used);
    const ingredients = r.ingredients.map((ing): Ingredient => {
      if (typeof ing.quantity === 'number') {
        report.alreadyQuantified++;
        return { ...ing };
      }
      const c = corr?.get(ing.name);
      if (c) used.add(ing.name);
      if (c && c.kind === 'amount' && typeof c.quantity === 'number') {
        report.amountsApplied++;
        return normalizeIngredient({
          name: ing.name, quantity: c.quantity, quantityMax: c.quantityMax, unit: c.unit,
        });
      }
      // fuzzy / 无匹配 / amount 但 quantity 非数字:保留已有模糊 note,否则落「适量」
      report.fuzzyMarked++;
      const existing = ing.note?.trim();
      return existing ? { name: ing.name, note: existing } : { name: ing.name, note: FUZZY_NOTE };
    });
    return { ...r, ingredients };
  });

  for (const [id, m] of byId) {
    const used = usedByRecipe.get(id) ?? new Set<string>();
    for (const name of m.keys()) if (!used.has(name)) report.unmatched++;
  }

  return { recipes: out, report };
}

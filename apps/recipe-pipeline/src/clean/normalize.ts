import type { Ingredient } from './schema';

/**
 * 「LLM 校验后结构 → 无损数字结构」的字段净化边界。
 *
 * 输入已是 schema 校验过的新结构(quantity/quantityMax 是 number,见 IngredientSchema),
 * 这里只做收敛:空 unit 省略、空 note 省略、quantityMax 不大于下界则丢弃、绝不产出空字符串。
 * - quantity 为 number → 透传(范围时连 quantityMax)。
 * - 无 quantity 但带 note(模糊量,如「适量」「一小把」)→ 清洗后(去 markdown/纯数字/公式)保留。
 * - 完全无量 → 只留 name。
 */
export interface IngredientLike {
  name: string;
  quantity?: number;
  quantityMax?: number;
  unit?: string;
  note?: string;
}

// 源「计算」段的公式标记:乘式与加式残留若漏进 note 一律剔除
const FORMULA_MUL_RE = /[*×]|份数|人份|\d+\s*人/;
const FORMULA_ADD_RE = /\+/;
// note 清洗:剔除 markdown 残留与公式标记
const MD_RESIDUE_RE = /!?\[[^\]]*\]\([^)]*\)|[*_`#]/g;

/** 清洗模糊词:去 markdown/公式标记并 trim;只剩纯数字/空 → 无效(返回空)。 */
function cleanNote(text: string): string {
  const cleaned = text.replace(MD_RESIDUE_RE, '').trim();
  if (!cleaned) return '';
  if (FORMULA_MUL_RE.test(cleaned) || FORMULA_ADD_RE.test(cleaned)) return '';
  if (/^\d+(\.\d+)?$/.test(cleaned)) return '';
  return cleaned;
}

export function normalizeIngredient(i: IngredientLike): Ingredient {
  const name = i.name;
  const u = (i.unit ?? '').trim();
  const out: Ingredient = { name };
  const setUnit = () => { if (u) out.unit = u; };

  // 已是新结构(quantity 是 number):直接派生,只做字段净化(空 unit 省略、空 note 省略)
  if (typeof i.quantity === 'number') {
    out.quantity = i.quantity;
    if (typeof i.quantityMax === 'number' && i.quantityMax > i.quantity) {
      out.quantityMax = i.quantityMax;
    }
    setUnit();
    return out;
  }
  // 无 quantity 但已带 note(新结构的模糊量):清洗后保留
  if (i.note !== undefined) {
    const fuzzy = cleanNote(i.note);
    if (fuzzy) out.note = fuzzy;
    return out;
  }

  // 完全无量 → 只留 name
  return out;
}

import * as v from 'valibot';

export const CATEGORIES = [
  '主食', '半成品', '早餐', '水产', '汤羹', '甜品', '素菜', '荤菜', '酱料', '饮品',
] as const;

export type Category = (typeof CATEGORIES)[number];

export const IngredientSchema = v.object({
  name: v.pipe(v.string(), v.minLength(1)),
  quantity: v.string(),
  unit: v.string(),
  amount: v.string(),
});

export const CleanRecipeSchema = v.object({
  id: v.pipe(v.string(), v.minLength(1)),
  name: v.pipe(v.string(), v.minLength(1)),
  category: v.picklist(CATEGORIES),
  difficulty: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(5)),
  cookingMinutes: v.pipe(v.number(), v.integer(), v.minValue(1)),
  description: v.string(),
  ingredients: v.array(IngredientSchema),
  steps: v.array(v.string()),
  tags: v.array(v.string()),
  imageUrl: v.nullable(v.string()),
  remoteVersion: v.pipe(v.number(), v.integer()),
  clientUpdatedAt: v.nullable(v.string()),
  deletedAt: v.nullable(v.string()),
});

export type CleanRecipe = v.InferOutput<typeof CleanRecipeSchema>;

export const EnrichmentSchema = v.object({
  category: v.picklist(CATEGORIES),
  difficulty: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(5)),
  cookingMinutes: v.pipe(v.number(), v.integer(), v.minValue(1)),
  description: v.string(),
  ingredients: v.array(IngredientSchema),
  steps: v.array(v.string()),
  tags: v.array(v.string()),
});

export type Enrichment = v.InferOutput<typeof EnrichmentSchema>;

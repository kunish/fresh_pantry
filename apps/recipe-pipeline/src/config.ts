import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export const config = {
  outPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  existingPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  imagesDir: resolve(root, '../ios/FreshPantry/Resources/RecipeImages'),
  rejectsPath: resolve(root, 'data/rejects.json'),
  sourcesPath: resolve(root, 'data/sources.json'),
  attributionsPath: resolve(root, 'data/image-attributions.json'),
  workDir: resolve(root, '.cache'),
  // 为仍缺图的菜谱联网补封面(默认走免 key 的 Openverse,覆盖有限,故 opt-in)。
  // 全网最佳匹配 + 视觉校验的全量补图由 ultracode workflow 完成,不靠这条默认路径。
  acquireImages: process.env.RECIPE_ACQUIRE_IMAGES === '1',
  model: process.env.RECIPE_MODEL ?? 'anthropic/claude-sonnet-4-6',
  // 'xhigh' 在 deepseek-v4-pro 上映射到 "max" 思考档(pi-ai thinkingLevelMap)
  thinkingLevel: (process.env.RECIPE_THINKING ?? 'xhigh') as 'off' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh',
  concurrency: Number(process.env.RECIPE_CONCURRENCY ?? '6'),
};

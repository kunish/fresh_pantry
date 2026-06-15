import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const recipeModel = process.env.RECIPE_MODEL ?? '@cf/moonshotai/kimi-k2.7-code';
// RECIPE_MODEL 以 @cf/ 开头 → 走 CloudflareEnricher(直连 OpenAI 兼容端点),否则走 flue。
const useCloudflare = recipeModel.startsWith('@cf/');
const cloudflareBaseUrl = process.env.CLOUDFLARE_AI_BASE_URL;
if (useCloudflare && !cloudflareBaseUrl) {
  throw new Error('CLOUDFLARE_AI_BASE_URL 未设置(Cloudflare 模式需要此变量,形如 https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/ai/v1)');
}

export const config = {
  outPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  existingPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  imagesDir: resolve(root, '../ios/FreshPantry/Resources/RecipeImages'),
  rejectsPath: resolve(root, 'data/rejects.json'),
  sourcesPath: resolve(root, 'data/sources.json'),
  attributionsPath: resolve(root, 'data/image-attributions.json'),
  videoAttributionsPath: resolve(root, 'data/video-attributions.json'),
  workDir: resolve(root, '.cache'),
  acquireImages: process.env.RECIPE_ACQUIRE_IMAGES === '1',
  acquireVideos: process.env.RECIPE_ACQUIRE_VIDEOS === '1',
  model: recipeModel,
  useCloudflare,
  cloudflare: {
    baseUrl: cloudflareBaseUrl ?? '',
    apiKey: process.env.CLOUDFLARE_AI_API_KEY ?? '',
    maxTokens: Number(process.env.RECIPE_MAX_TOKENS ?? '8192'),
  },
  thinkingLevel: (process.env.RECIPE_THINKING ?? 'xhigh') as 'off' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh',
  concurrency: Number(process.env.RECIPE_CONCURRENCY ?? '6'),
};

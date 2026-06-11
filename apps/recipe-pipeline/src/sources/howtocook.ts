import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, readdir, stat } from 'node:fs/promises';
import { join, relative, basename } from 'node:path';
import type { RecipeSource, RawRecipe, SourceContext } from './types';
import { parseHowtocook } from '../parse/howtocook-parser';
import { mapHowtocookCategory } from '../parse/category-map';

const exec = promisify(execFile);
const REPO = 'https://github.com/Anduin2017/HowToCook.git';

export function howtocookIdFromPath(relPath: string): string {
  const noPrefix = relPath.replace(/^dishes\//, '').replace(/\.md$/, '');
  return `howtocook:${noPrefix}`;
}

export function rawFromMarkdown(relPath: string, md: string): RawRecipe {
  const parsed = parseHowtocook(md);
  const engCat = relPath.replace(/^dishes\//, '').split('/')[0];
  return {
    id: howtocookIdFromPath(relPath),
    sourceId: 'howtocook',
    sourceRef: relPath,
    name: parsed.name || basename(relPath, '.md'),
    sourceCategory: mapHowtocookCategory(engCat),
    sourceDifficulty: parsed.difficulty,
    description: parsed.description,
    rawIngredients: parsed.rawIngredients,
    portionText: parsed.portionText,
    steps: parsed.steps,
    imageUrl: null,
  };
}

async function* walkMarkdown(dir: string, root: string): AsyncIterable<string> {
  for (const entry of await readdir(dir)) {
    const full = join(dir, entry);
    const s = await stat(full);
    if (s.isDirectory()) yield* walkMarkdown(full, root);
    else if (entry.endsWith('.md') && entry !== 'README.md') yield relative(root, full);
  }
}

export function howtocookSource(): RecipeSource {
  return {
    id: 'howtocook',
    kind: 'deterministic',
    async *collect(ctx: SourceContext): AsyncIterable<RawRecipe> {
      const repoDir = join(ctx.workDir, 'howtocook');
      await exec('git', ['clone', '--depth', '1', REPO, repoDir]).catch((e) => {
        ctx.log(`clone skipped/failed (${String(e)}); 假定已存在 ${repoDir}`);
      });
      const dishesDir = join(repoDir, 'dishes');
      for await (const relPath of walkMarkdown(dishesDir, repoDir)) {
        const md = await readFile(join(repoDir, relPath), 'utf8');
        const raw = rawFromMarkdown(relPath, md);
        if (raw.rawIngredients.length || raw.steps.length) yield raw;
      }
    },
  };
}

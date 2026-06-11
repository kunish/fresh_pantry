import type { RecipeSource } from './types';
import { howtocookSource } from './howtocook';
import type { RecipeEnricher } from '../clean/enrich';

export interface SourceConfig {
  type: 'howtocook' | 'markdown-repo' | 'url-batch';
  enabled?: boolean;
  [key: string]: unknown;
}

export interface SourcesFile {
  sources: SourceConfig[];
}

export function buildSources(file: SourcesFile, _enricher: RecipeEnricher): RecipeSource[] {
  return file.sources
    .filter((s) => s.enabled !== false)
    .map((s) => {
      switch (s.type) {
        case 'howtocook':
          return howtocookSource();
        default:
          throw new Error(`source type 未实现(将在 Milestone 7 接入): ${s.type}`);
      }
    });
}

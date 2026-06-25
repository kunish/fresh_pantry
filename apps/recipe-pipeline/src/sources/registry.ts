import type { RecipeSource } from './types';
import { howtocookSource } from './howtocook';
import type { RecipeEnricher } from '../clean/enrich';

export type SourceConfig =
  | { type: 'howtocook'; enabled?: boolean };

export interface SourcesFile {
  sources: SourceConfig[];
}

export function buildSources(file: SourcesFile, enricher: RecipeEnricher): RecipeSource[] {
  return file.sources
    .filter((s) => s.enabled !== false)
    .map((s): RecipeSource => {
      switch (s.type) {
        case 'howtocook':
          return howtocookSource();
      }
    });
}

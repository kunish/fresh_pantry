import type { RecipeSource } from './types';
import { howtocookSource } from './howtocook';
import { markdownRepoSource, type MarkdownRepoConfig } from './markdown-repo';
import { urlBatchSource, type UrlBatchConfig } from './url-batch';
import type { RecipeEnricher } from '../clean/enrich';

export type SourceConfig =
  | { type: 'howtocook'; enabled?: boolean }
  | ({ type: 'markdown-repo'; enabled?: boolean } & MarkdownRepoConfig)
  | ({ type: 'url-batch'; enabled?: boolean } & UrlBatchConfig);

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
        case 'markdown-repo':
          return markdownRepoSource(s);
        case 'url-batch':
          return urlBatchSource(s, enricher);
      }
    });
}

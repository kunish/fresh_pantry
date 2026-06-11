import { describe, it, expect } from 'vitest';
import { howtocookIdFromPath, rawFromMarkdown } from '../src/sources/howtocook';

describe('howtocookIdFromPath', () => {
  it('直挂文件', () => {
    expect(howtocookIdFromPath('dishes/vegetable_dish/凉拌黄瓜.md'))
      .toBe('howtocook:vegetable_dish/凉拌黄瓜');
  });
  it('子目录文件', () => {
    expect(howtocookIdFromPath('dishes/vegetable_dish/鸡蛋花/鸡蛋花.md'))
      .toBe('howtocook:vegetable_dish/鸡蛋花/鸡蛋花');
  });
});

describe('rawFromMarkdown', () => {
  it('组装 RawRecipe:分类来自目录、难度来自解析', () => {
    const md = '# 凉拌黄瓜的做法\n\n描述。\n\n预估烹饪难度：★\n\n## 必备原料和工具\n\n* 黄瓜\n\n## 操作\n\n1. 切\n';
    const r = rawFromMarkdown('dishes/vegetable_dish/凉拌黄瓜.md', md);
    expect(r.id).toBe('howtocook:vegetable_dish/凉拌黄瓜');
    expect(r.sourceCategory).toBe('素菜');
    expect(r.sourceDifficulty).toBe(1);
    expect(r.name).toBe('凉拌黄瓜');
    expect(r.rawIngredients).toEqual(['黄瓜']);
    expect(r.sourceId).toBe('howtocook');
  });
});

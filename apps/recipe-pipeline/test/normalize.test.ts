import { describe, it, expect } from 'vitest';
import { normalizeIngredient } from '../src/clean/normalize';

describe('normalizeIngredient:已是新结构(number)的对象幂等收敛', () => {
  it('numeric quantity 透传,空 unit 省略', () => {
    expect(normalizeIngredient({ name: '盐', quantity: 200, unit: '克' }))
      .toEqual({ name: '盐', quantity: 200, unit: '克' });
    expect(normalizeIngredient({ name: '盐', quantity: 200, unit: '' }))
      .toEqual({ name: '盐', quantity: 200 });
  });
  it('范围结构透传;quantityMax 不大于下界则丢弃', () => {
    expect(normalizeIngredient({ name: '糖', quantity: 6, quantityMax: 15, unit: '克' }))
      .toEqual({ name: '糖', quantity: 6, quantityMax: 15, unit: '克' });
    expect(normalizeIngredient({ name: '糖', quantity: 6, quantityMax: 6, unit: '克' }))
      .toEqual({ name: '糖', quantity: 6, unit: '克' });
  });
  it('已带 note 的模糊量透传(清洗后保留)', () => {
    expect(normalizeIngredient({ name: '盐', note: '适量' })).toEqual({ name: '盐', note: '适量' });
  });
  it('note 清洗:markdown 残留/公式/纯数字 → 无效,丢弃', () => {
    expect(normalizeIngredient({ name: '盐', note: '`适量`' })).toEqual({ name: '盐', note: '适量' });
    expect(normalizeIngredient({ name: '盐', note: '200' })).toEqual({ name: '盐' });
    expect(normalizeIngredient({ name: '盐', note: 'X * 份数' })).toEqual({ name: '盐' });
  });
  it('完全无量 → 只留 name(quantity/unit/note 全省略)', () => {
    expect(normalizeIngredient({ name: '盐' })).toEqual({ name: '盐' });
  });
  it('绝不产出 amount/空 unit 字段', () => {
    const r = normalizeIngredient({ name: '盐', quantity: 200, unit: '' });
    expect('amount' in r).toBe(false);
    expect('unit' in r).toBe(false);
  });
});

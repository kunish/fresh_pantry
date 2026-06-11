import { describe, it, expect } from 'vitest';
import { mapHowtocookCategory, HOWTOCOOK_CATEGORY_MAP } from '../src/parse/category-map';

describe('mapHowtocookCategory', () => {
  it('全部 10 个英文目录都有映射', () => {
    expect(Object.keys(HOWTOCOOK_CATEGORY_MAP)).toHaveLength(10);
  });
  it.each([
    ['aquatic', '水产'], ['breakfast', '早餐'], ['condiment', '酱料'],
    ['dessert', '甜品'], ['drink', '饮品'], ['meat_dish', '荤菜'],
    ['semi-finished', '半成品'], ['soup', '汤羹'], ['staple', '主食'],
    ['vegetable_dish', '素菜'],
  ])('%s -> %s', (en, zh) => {
    expect(mapHowtocookCategory(en)).toBe(zh);
  });
  it('未知目录返回 undefined', () => {
    expect(mapHowtocookCategory('unknown')).toBeUndefined();
  });
});

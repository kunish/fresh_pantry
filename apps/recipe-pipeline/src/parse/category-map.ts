import type { Category } from '../clean/schema';

export const HOWTOCOOK_CATEGORY_MAP: Record<string, Category> = {
  aquatic: '水产',
  breakfast: '早餐',
  condiment: '酱料',
  dessert: '甜品',
  drink: '饮品',
  meat_dish: '荤菜',
  'semi-finished': '半成品',
  soup: '汤羹',
  staple: '主食',
  vegetable_dish: '素菜',
};

export function mapHowtocookCategory(dir: string): Category | undefined {
  return HOWTOCOOK_CATEGORY_MAP[dir];
}

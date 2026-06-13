import { createHash } from 'node:crypto';
import { extname } from 'node:path';

/**
 * Supabase Storage 的对象 key 不接受 CJK 等非 ASCII 字符(返回 InvalidKey),
 * 而本地封面名带中文菜名(`web_aquatic_咖喱炒蟹.jpg`)。这里把本地文件名映射成
 * 稳定的 ASCII 安全 key:保留可读的 ASCII 前缀 + 原文件名 sha1 短哈希消歧。
 *
 * 上传(upload-images)与 URL 改写(rewrite-image-urls)共用此函数,保证
 * storage 里的 key 与 imageUrl 指向一致。确定性、幂等、可重复跑。
 */
export function storageKeyFor(filename: string): string {
  const ext = extname(filename).toLowerCase() || '.jpg';
  const stem = filename.slice(0, filename.length - extname(filename).length);
  const ascii = stem.replace(/[^A-Za-z0-9._-]+/g, '_').replace(/^_+|_+$/g, '');
  const hash = createHash('sha1').update(filename).digest('hex').slice(0, 10);
  return `${ascii ? ascii + '_' : ''}${hash}${ext}`;
}

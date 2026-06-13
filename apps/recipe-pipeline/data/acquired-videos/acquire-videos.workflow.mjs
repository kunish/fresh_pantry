export const meta = {
  name: 'acquire-recipe-videos',
  description: '为每道菜联网搜一条「做法视频」外链 + 校验相关性(不下载,只存外链)',
  phases: [
    { title: 'Acquire', detail: '每道菜一个 agent:WebSearch 找视频 → WebFetch 校验是这道菜 → 回外链' },
  ],
};

const A = typeof args === 'string' ? JSON.parse(args) : (args ?? {});
const dishesPath = A.dishesPath;
const acquiredDir = A.acquiredDir;
const all = require(dishesPath); // [{i,id,name,category,ings}]
const indices = A.indices
  ?? (A.start != null
    ? Array.from({ length: A.end - A.start }, (_, i) => i + A.start)
    : Array.from({ length: all.length }, (_, i) => i));
log(`args: ${indices.length} dishes,acquiredDir=${acquiredDir ? 'set' : 'MISSING'}`);

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['index', 'id', 'ok', 'reason'],
  properties: {
    index: { type: 'integer' },
    id: { type: 'string' },
    ok: { type: 'boolean', description: '是否找到一条通过校验的视频外链' },
    videoUrl: { type: ['string', 'null'], description: '视频观看页 URL(http/https),如 B站/YouTube/下厨房' },
    sourcePage: { type: ['string', 'null'], description: '同 videoUrl 或承载页' },
    title: { type: ['string', 'null'], description: '视频标题' },
    provider: { type: ['string', 'null'], enum: ['bilibili', 'youtube', 'xiachufang', 'douguo', 'meishichina', 'other', null] },
    confidence: { type: ['string', 'null'], enum: ['high', 'medium', 'low', null] },
    reason: { type: 'string', description: '一句话:采用了什么视频 / 为何没找到' },
  },
};

function buildPrompt(idx) {
  const d = all[idx];
  const metaPath = `${acquiredDir}/${idx}.json`;
  return `你的任务:为一道中文家常菜从互联网找一条「做法/教程视频」的观看页外链,做相关性校验,然后把结果写成一行 JSON。这是 fresh_pantry app 的菜谱视频补齐。视频不下载、只记外链 URL。

## 这道菜
- index: ${idx}
- id: ${d.id}
- 菜名: ${d.name}
- 分类: ${d.category}
- 主料: ${(d.ings ?? []).join('、') || '(未知)'}
- 目标元数据文件: ${metaPath}

## 第 1 步:搜候选视频
用 WebSearch 搜:「${d.name} 做法 视频」「${d.name} 教程」「${d.name} recipe video」。
优先来源(可信、长期可用):
- 哔哩哔哩 bilibili.com(中文做菜视频最丰富)
- YouTube youtube.com / youtu.be
- 下厨房 xiachufang.com、豆果 douguo.com、美食天下 meishichina.com 的视频页
收集 3~6 个候选视频观看页 URL。

## 第 2 步:校验「确为这道菜的做法视频」
对最相关的 1~3 个候选,用 WebFetch 打开,prompt 让它「提取视频标题、UP主/作者、简介」,据此判断:
- 标题/简介确实是在做「${d.name}」(或其明确别名),不是别的菜、不是 vlog/探店/无关内容;
- 是「做法/教程」类(有烹饪步骤),不是纯吃播;
- 链接是公开可看的观看页(不是登录墙/失效页)。
给 confidence:high(标题直指这道菜的做法)/ medium(很可能是)/ low(不确定,不采用)。

## 第 3 步:写结果
- 找到(confidence high/medium):用 Write 把一行 JSON 写到 ${metaPath}:
  {"index":${idx},"id":"${d.id}","ok":true,"videoUrl":"<观看页URL>","sourcePage":"<同上或承载页>","title":"<视频标题>","provider":"bilibili|youtube|xiachufang|douguo|meishichina|other","confidence":"high|medium","reason":"<简述>"}
- 没找到合适的:**不要硬塞**,Write ${metaPath} 写:
  {"index":${idx},"id":"${d.id}","ok":false,"videoUrl":null,"sourcePage":null,"title":null,"provider":null,"confidence":null,"reason":"<尝试了什么、为何没采用>"}

## 约束
- 绝不修改 howtocook.json 或任何其它已有文件,只新增 ${metaPath}。
- videoUrl 必须是 http(s) 开头的真实观看页;拿不准就 ok:false,宁缺毋滥。
- 高效:别陷在一道菜上无限搜;候选耗尽就如实 ok:false。
- 最后用 StructuredOutput 返回与 ${metaPath} 一致的结构。`;
}

phase('Acquire');
const results = await parallel(
  indices.map((idx) => () =>
    agent(buildPrompt(idx), {
      label: `vid:${idx}`,
      phase: 'Acquire',
      schema: SCHEMA,
      agentType: 'general-purpose',
    }),
  ),
);

const got = results.filter(Boolean);
const ok = got.filter((r) => r.ok);
log(`acquire 完成:${ok.length}/${indices.length} 条视频外链,${indices.length - ok.length} 条未匹配`);
return { requested: indices.length, ok: ok.length, failed: indices.length - ok.length, results: got };

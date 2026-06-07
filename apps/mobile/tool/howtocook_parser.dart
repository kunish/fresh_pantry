import 'package:fresh_pantry/models/recipe.dart';

/// HowToCook `dishes/<dir>/` 目录名 → 中文类别。
const Map<String, String> howtocookCategoryByDir = {
  'aquatic': '水产',
  'breakfast': '早餐',
  'condiment': '酱料',
  'dessert': '甜品',
  'drink': '饮品',
  'meat_dish': '荤菜',
  'semi-finished': '半成品',
  'soup': '汤羹',
  'staple': '主食',
  'vegetable_dish': '素菜',
};

const Map<int, int> _minutesByDifficulty = {1: 15, 2: 25, 3: 40, 4: 60, 5: 90};
const int _defaultMinutes = 30;

/// GitHub LFS media 端点前缀：HowToCook 图片用 Git LFS 存储，jsDelivr/raw 只返回
/// 131 字节的 LFS pointer，唯有 media 端点返回真实图片。import 据此下载到本地 assets。
const String _imageRemotePrefix =
    'https://media.githubusercontent.com/media/Anduin2017/HowToCook/master/dishes';

final RegExp _bullet = RegExp(r'^\s*[*-]\s+(.*)$');
final RegExp _ordered = RegExp(r'^\s*\d+\.\s+(.*)$');
// URL 段允许一层嵌套括号：上游文件名常含括号（如「石凉粉(冰粉)成品1.jpg」），
// 朴素的 [^)]* 会在第一个 ) 处截断 → 图片 URL 缺尾、步骤链接残留「).md」。
const String _mdUrl = r'((?:[^()]|\([^()]*\))*)';
final RegExp _image = RegExp(r'!\[([^\]]*)\]\(' + _mdUrl + r'\)');
final RegExp _link = RegExp(r'\[([^\]]*)\]\(' + _mdUrl + r'\)');

/// 设备/专有器具关键词：项中出现即判为工具（长词，不会作为食材子串）。
const List<String> _toolKeywords = [
  '电饼铛', '烤箱', '烤盘', '烤架', '烤网', '微波炉', '空气炸锅', '电饭煲', '电饭锅',
  '电炖锅', '电压力锅', '高压锅', '压力锅', '蒸笼', '笼屉', '蒸格', '笊篱', '漏勺',
  '漏网', '锅铲', '铲子', '打蛋器', '搅拌器', '搅拌机', '搅拌棒', '破壁机', '榨汁机',
  '料理机', '料理棒', '擀面杖', '案板', '砧板', '菜板', '筛网', '筛子', '温度计',
  '保鲜膜', '保鲜袋', '密封袋', '锡纸', '油纸', '硅油纸', '烘焙纸', '烘焙油纸',
  '厨房纸', '吸油纸', '牙签', '喷壶', '油刷', '毛刷', '刷子', '量杯', '量勺', '刮刀',
  '削皮刀', '菜刀', '水果刀', '餐刀', '砍刀', '手套', '模具', '裱花', '吧勺', '克称',
  '克数称', '电子秤', '厨房秤', '夹子', '筷子', '勺子', '铁勺', '汤勺', '披萨石',
  '锅盖', '容器', '打蛋', '试剂瓶',
];

/// 通用器皿单字：项（剥离说明/数量后）以此结尾即判为工具。
const List<String> _toolSuffixes = [
  '锅', '刀', '勺', '碗', '盆', '盘', '碟', '杯', '笼', '屉', '夹',
];

/// 丢弃型行首前缀：以这些词 + 冒号开头的行整体丢弃（工具说明/旁注，非食材）。
final RegExp _dropPrefix = RegExp(
  r'^(工具|所需工具|必备工具|所必要的工具|注|备注|提示|说明|tips|小贴士|小技巧|PS)\s*[：:]',
  caseSensitive: false,
);

/// 食材分组标题前缀：去掉"前缀："后保留后半（如「必备：厨房纸」→「厨房纸」）。
const List<String> _groupPrefixes = [
  '主料', '辅料', '配料', '主食材', '副食材', '主材', '原料', '所需原料', '可选原料',
  '可选材料', '材料', '香料', '全香料', '调味料', '调料', '腌料', '酱料', '酱汁',
  '食材', '必备', '可选', '备选',
];

// 数量描述：数字（含范围 50-100）或中文数字 + 量词。
const String _qtyUnits =
    r'(g|kg|克|千克|ml|毫升|升|cm|mm|个|只|颗|粒|块|片|条|根|把|勺|匙|斤|两|袋|盒|包|瓶|罐|朵|头|瓣|节|段|张|份|双|对)';

/// 结尾数量（「香菜一颗」→「香菜」、「牛奶 50-100g」→「牛奶」）。
final RegExp _trailingQty = RegExp(
  r'(\d+(\.\d+)?([-~～]\d+(\.\d+)?)?|[一二两三四五六七八九十几半]+)\s*'
  '$_qtyUnits\$',
);

/// 前置数量（「125ml 淡奶油」→「淡奶油」、「1 袋 半成品意面」→「半成品意面」）；
/// 要求其后有空格分隔食材名，避免误伤「八角」这类。
final RegExp _leadingQty = RegExp(
  r'^(\d+(\.\d+)?([-~～]\d+(\.\d+)?)?)\s*'
  '$_qtyUnits?'
  r'\s+',
);

/// 说明句碎片（拆分逗号后混入的整句）：含句末标点、说明词或过长，判为非食材。
const List<String> _noteWords = [
  '即可', '能够', '可以', '根据', '依据', '建议', '自行', '参见', '二选一', '口味',
  '适量', '少许', '若干', '左右', '喜欢', '添加', '需要', '如下', '等量', '以上', '以下',
];
final RegExp _sentenceEnd = RegExp(r'[。！？!?]');

bool _looksLikeNote(String s) {
  if (s.length > 12) return true;
  if (_sentenceEnd.hasMatch(s)) return true;
  return _noteWords.any(s.contains);
}

/// 解析单篇 HowToCook 菜谱 markdown 为 [Recipe]。
/// [relativePath] 是相对 `dishes/` 的路径，例如 `meat_dish/可乐鸡翅.md`。
/// 当文档不是菜谱（无 `# ` 标题、或无 `## 操作` 段）时返回 null。
Recipe? parseHowToCookMarkdown(
  String markdown, {
  required String relativePath,
}) {
  final lines = markdown.split('\n');

  final title = _firstTitle(lines);
  if (title == null) return null;
  final name = title.endsWith('的做法')
      ? title.substring(0, title.length - 3)
      : title;

  final sections = _splitSections(lines);
  final operation = sections['操作'];
  if (operation == null) return null;

  final difficulty = _parseDifficulty(lines);
  final ingredients = _parseIngredients(sections['必备原料和工具'] ?? const []);
  final steps = _parseSteps(operation);
  final description = _parseDescription(lines);
  final category = howtocookCategoryByDir[_firstSegment(relativePath)] ?? '其他';
  final cookingMinutes = _minutesByDifficulty[difficulty] ?? _defaultMinutes;
  final imageUrl = _parseImageUrl(lines, relativePath);
  final id = 'howtocook:${relativePath.replaceAll(RegExp(r'\.md$'), '')}';

  return Recipe(
    id: id,
    name: name,
    category: category,
    difficulty: difficulty,
    cookingMinutes: cookingMinutes,
    description: description,
    ingredients: ingredients,
    steps: steps,
    tags: [category],
    imageUrl: imageUrl,
  );
}

String? _firstTitle(List<String> lines) {
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('# ')) return t.substring(2).trim();
  }
  return null;
}

String _firstSegment(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/');
  final idx = normalized.indexOf('/');
  return idx == -1 ? '' : normalized.substring(0, idx);
}

/// 切成 `## ` 段：标题（去掉 `## `）→ 段内行。
Map<String, List<String>> _splitSections(List<String> lines) {
  final sections = <String, List<String>>{};
  String? current;
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('## ')) {
      current = t.substring(3).trim();
      sections[current] = <String>[];
    } else if (current != null) {
      sections[current]!.add(line);
    }
  }
  return sections;
}

int _parseDifficulty(List<String> lines) {
  for (final line in lines) {
    if (line.contains('预估烹饪难度')) {
      return '★'.allMatches(line).length.clamp(0, 5);
    }
  }
  return 0;
}

/// 食材名来自「必备原料和工具」段。上游把工具、旁注、分组前缀都平铺进同一
/// bullet 列表，这里逐项清洗后剔除非食材：
/// 1. 若该段有 `### 工具`/`### 原料` 子标题，工具子标题下的项整体跳过；
/// 2. 行级清洗（去 markdown 标记、`[可选]` 前缀、分组前缀、括号说明、结尾数量）；
/// 3. 对清洗后的核心词判定器具/工具（先剥离再判定，避免误伤说明里提到工具的食材）。
List<RecipeIngredient> _parseIngredients(List<String> body) {
  final hasSubhead = body.any((l) => l.trim().startsWith('### '));
  final result = <RecipeIngredient>[];
  var inToolGroup = false;
  for (final line in body) {
    final t = line.trim();
    if (t.startsWith('### ')) {
      inToolGroup = t.substring(4).trim().contains('工具');
      continue;
    }
    if (hasSubhead && inToolGroup) continue;
    final m = _bullet.firstMatch(line);
    if (m == null) continue;
    for (final name in _ingredientsFromLine(m.group(1)!.trim())) {
      result.add(RecipeIngredient(name: name));
    }
  }
  // Dedup via the model's single source of truth so the offline parser and the
  // runtime recipe sources collapse 味精-style duplicates identically.
  return dedupeRecipeIngredients(result);
}

/// 把一条原始 bullet 文本归一为食材名列表——上游常用顿号在一行里列举多个
/// 食材（「大肉、鸡蛋、豆皮」），故一行可能产出多项。工具/旁注/空项被滤除。
List<String> _ingredientsFromLine(String raw) {
  final body = _stripIngredientPrefix(raw);
  if (body == null) return const [];
  final names = <String>[];
  for (final seg in _splitEnumerations(body)) {
    final name = _finalizeIngredientName(seg);
    if (name != null && name.isNotEmpty) names.add(name);
  }
  return names;
}

/// 去 markdown 标记、`[可选]` 前缀、分组前缀；丢弃旁注（工具/注/PS…）与以冒号
/// 结尾的纯标题行。返回行主体（待拆分），无主体则 null。
String? _stripIngredientPrefix(String raw) {
  // 先清理内联 markdown（图片删、链接取文字、去加粗/行内代码），再做前缀处理；
  // 否则图片/链接里的标点会干扰后续按逗号/顿号的拆分。
  var s = _stripInlineMarkdown(raw);
  // 行首方括号标记，如 `[可选] 柠檬汁`。
  s = s.replaceAll(RegExp(r'^\s*\[[^\]]*\]\s*'), '').trim();
  if (s.isEmpty) return null;
  // 以冒号结尾的分组标题行（如「…其中应该包含：」），真正食材在其下子项里。
  if (s.endsWith('：') || s.endsWith(':')) return null;
  // 丢弃型前缀（工具/注/PS…）。
  if (_dropPrefix.hasMatch(s)) return null;
  // 冒号分组前缀。
  final colon = RegExp(r'^([^：:]{1,10})[：:]\s*(.*)$').firstMatch(s);
  if (colon != null) {
    final prefix = colon.group(1)!.trim();
    final rest = colon.group(2)!.trim();
    if (_groupPrefixes.contains(prefix)) {
      if (rest.isEmpty) return null; // 纯分组标题行（如「原料:」）。
      s = rest; // 「必备：厨房纸」→「厨房纸」。
    } else {
      s = prefix; // 「白砂糖：60g」→「白砂糖」。
    }
  }
  return s;
}

/// 按括号外的列举分隔符（顿号、逗号、分号）拆分；括号内的分隔符不切，避免切坏
/// 注释里的标点。逗号也是上游常见的食材列举分隔（「油，盐，生抽」）。
List<String> _splitEnumerations(String s) {
  const separators = {'、', '，', ',', '；', ';', '+', '＋'};
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  for (final ch in s.split('')) {
    if (ch == '（' || ch == '(') {
      depth++;
    } else if (ch == '）' || ch == ')') {
      if (depth > 0) depth--;
    }
    if (depth == 0 && separators.contains(ch)) {
      parts.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  parts.add(buf.toString());
  return parts;
}

/// 对单个列举项剥括号说明（「鸡蛋（可选）」→「鸡蛋」）与结尾数量（「香菜一颗」
/// →「香菜」），再判定器具/工具；非食材返回 null。
String? _finalizeIngredientName(String seg) {
  var s = seg.trim();
  if (s.isEmpty) return null;
  // 剥括号说明：食材名在第一个括号之前。
  final br = s.indexOf(RegExp(r'[（(]'));
  if (br > 0) {
    s = s.substring(0, br).trim();
  } else if (br == 0) {
    return null; // 整项以括号开头，多为纯说明。
  }
  // 剥前置与结尾数量（「125ml 淡奶油」「香菜一颗」）。
  s = s.replaceFirst(_leadingQty, '').trim();
  s = s.replaceFirst(_trailingQty, '').trim();
  if (s.isEmpty) return null;
  // 说明句碎片（逗号拆分后混入的整句）。
  if (_looksLikeNote(s)) return null;
  // 工具判定（对剥离后的核心词）。
  if (_toolKeywords.any(s.contains)) return null;
  if (_toolSuffixes.any(s.endsWith)) return null;
  return s;
}

/// 仅取顶层有序项（`1. `…）作为步骤；缩进的子贴士忽略。
/// 每条步骤清理内联 markdown（图片删除、链接保留可见文字、去加粗/行内代码标记）。
List<String> _parseSteps(List<String> body) {
  final result = <String>[];
  for (final line in body) {
    if (line.startsWith(' ') || line.startsWith('\t')) continue;
    final m = _ordered.firstMatch(line);
    if (m == null) continue;
    final step = _stripInlineMarkdown(m.group(1)!.trim());
    if (step.isNotEmpty) result.add(step);
  }
  return result;
}

/// 去掉步骤文本里的内联 markdown：图片整体删除、链接保留可见文字、去掉加粗与
/// 行内代码标记。先处理图片再处理链接，避免链接正则吃掉图片的 `[..]()` 残留 `!`。
String _stripInlineMarkdown(String text) {
  var s = text.replaceAll(_image, '');
  s = s.replaceAllMapped(_link, (m) => m.group(1) ?? '');
  s = s.replaceAll('`', '').replaceAll(RegExp(r'\*\*|__'), '');
  return s.trim();
}

/// 从 md 的图片引用生成成品图 URL。选取顺序：
/// 1. alt 或文件名含「成品」「预览」；2. 「## 操作」段之前的第一张；3. 第一张。
/// 仓库内相对路径转成 LFS media 端点 URL（路径段按需百分号编码），供 import 下载。
String? _parseImageUrl(List<String> lines, String relativePath) {
  final opIdx = lines.indexWhere((l) => l.trim() == '## 操作');
  final imgs = <_ImgRef>[];
  for (var i = 0; i < lines.length; i++) {
    for (final m in _image.allMatches(lines[i])) {
      final path = (m.group(2) ?? '').trim();
      if (path.isEmpty) continue;
      imgs.add(_ImgRef(m.group(1) ?? '', path, i));
    }
  }
  if (imgs.isEmpty) return null;

  bool named(_ImgRef r) =>
      r.alt.contains('成品') ||
      r.alt.contains('预览') ||
      r.path.contains('成品') ||
      r.path.contains('预览');
  _ImgRef? pick;
  for (final r in imgs) {
    if (named(r)) {
      pick = r;
      break;
    }
  }
  if (pick == null && opIdx >= 0) {
    for (final r in imgs) {
      if (r.line < opIdx) {
        pick = r;
        break;
      }
    }
  }
  pick ??= imgs.first;

  if (pick.path.startsWith('http://') || pick.path.startsWith('https://')) {
    return pick.path;
  }
  return _toMediaUrl(pick.path, relativePath);
}

/// 把图片相对路径（相对菜谱 md 所在目录）解析为 LFS media 端点绝对 URL。
String? _toMediaUrl(String imagePath, String relativePath) {
  final segs = relativePath.replaceAll('\\', '/').split('/')..removeLast();
  for (final part in imagePath.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segs.isNotEmpty) segs.removeLast();
      continue;
    }
    segs.add(part);
  }
  if (segs.isEmpty) return null;
  final encoded = segs.map(Uri.encodeComponent).join('/');
  return '$_imageRemotePrefix/$encoded';
}

class _ImgRef {
  const _ImgRef(this.alt, this.path, this.line);
  final String alt;
  final String path;
  final int line;
}

/// 标题之后、`预估`/`## ` 之前的第一段非空文本。
String _parseDescription(List<String> lines) {
  final buffer = <String>[];
  var seenTitle = false;
  for (final line in lines) {
    final t = line.trim();
    if (!seenTitle) {
      if (t.startsWith('# ')) seenTitle = true;
      continue;
    }
    if (t.isEmpty) {
      if (buffer.isNotEmpty) break;
      continue;
    }
    if (t.startsWith('预估') || t.startsWith('#')) break;
    buffer.add(t);
  }
  return buffer.join(' ');
}

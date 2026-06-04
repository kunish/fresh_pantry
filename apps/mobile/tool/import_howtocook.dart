// tool/import_howtocook.dart
//
// 用法: dart run tool/import_howtocook.dart <HowToCook clone 路径> [输出路径]
// 先 clone 一份上游:
//   git clone --depth 1 https://github.com/Anduin2017/HowToCook /tmp/HowToCook
// 数据来源: https://github.com/Anduin2017/HowToCook (Unlicense)
// 仅在 macOS/Linux 上运行（路径分隔符按 / 处理）。
// 注意：默认输出路径是相对路径，请在 apps/mobile/ 目录下运行本脚本。
//
// 成品图：上游图片用 Git LFS 存储，解析器产出的是 media 端点 URL（唯一能取真图的
// 源）。本脚本逐张下载到 assets/recipes/images/，并把每条 recipe 的 imageUrl 改写为
// 本地 asset 路径——这样 app 完全离线、不依赖第三方 LFS 配额。已下载的图会跳过。
import 'dart:convert';
import 'dart:io';

import 'howtocook_parser.dart';

// 图片打包目录；asset key 即此相对路径，故本脚本须在 apps/mobile/ 下运行。
const String imageAssetDir = 'assets/recipes/images';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/import_howtocook.dart <HowToCook-clone-path> [out.json]',
    );
    exit(64);
  }
  final repoRoot = args[0];
  final outPath = args.length > 1 ? args[1] : 'assets/recipes/howtocook.json';

  final dishesDir = Directory('$repoRoot/dishes');
  if (!dishesDir.existsSync()) {
    stderr.writeln('dishes/ not found under "$repoRoot"');
    exit(66);
  }

  final mdFiles =
      dishesDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final httpClient = HttpClient();
  final recipes = <Map<String, dynamic>>[];
  var ok = 0;
  var skippedNotRecipe = 0; // 解析器返回 null（无标题/无操作段）
  var skippedEmpty = 0; // 无食材或无步骤
  var noDifficulty = 0; // 观察项：解析成功但难度未标注（difficulty==0）
  var imgDownloaded = 0;
  var imgCached = 0; // 已存在，跳过下载
  var imgFailed = 0; // 下载失败/非图片（如 LFS 配额耗尽）→ imageUrl 置 null
  for (final file in mdFiles) {
    final rel = file.path
        .substring(dishesDir.path.length + 1)
        .replaceAll('\\', '/');
    // Skip the upstream template under dishes/template/ (it has a title and an
    // 操作 section, so it would otherwise pass the recipe filter).
    if (rel.startsWith('template/')) {
      skippedNotRecipe++;
      continue;
    }
    final String content;
    try {
      content = file.readAsStringSync();
    } on Exception catch (e) {
      // 个别上游文件可能是非 UTF-8（如 GBK）；跳过并记录，别让整次导入中断。
      stderr.writeln('Skip (read error) $rel: $e');
      skippedNotRecipe++;
      continue;
    }
    final recipe = parseHowToCookMarkdown(content, relativePath: rel);
    if (recipe == null) {
      skippedNotRecipe++;
      continue;
    }
    if (recipe.ingredients.isEmpty || recipe.steps.isEmpty) {
      skippedEmpty++;
      continue;
    }
    if (recipe.difficulty == 0) noDifficulty++;

    final json = recipe.toJson();
    // 下载成品图到本地 assets，imageUrl 改写为 asset 路径；失败则置 null（显示占位）。
    final remote = recipe.imageUrl;
    if (remote != null &&
        (remote.startsWith('http://') || remote.startsWith('https://'))) {
      final assetPath = '$imageAssetDir/${_slug(recipe.id)}${_imageExt(remote)}';
      final outFile = File(assetPath);
      if (outFile.existsSync() && outFile.lengthSync() > 1000) {
        imgCached++;
        json['imageUrl'] = assetPath;
      } else if (await _downloadImage(httpClient, remote, outFile)) {
        imgDownloaded++;
        json['imageUrl'] = assetPath;
      } else {
        stderr.writeln('Image failed: ${recipe.id} ← $remote');
        imgFailed++;
        json['imageUrl'] = null;
      }
    }
    recipes.add(json);
    ok++;
  }
  httpClient.close();

  File(outPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(recipes));
  stdout.writeln(
    'Imported $ok recipes '
    '(skipped: $skippedNotRecipe non-recipe, $skippedEmpty empty; '
    '$noDifficulty have no difficulty label) → $outPath',
  );
  stdout.writeln(
    'Images: $imgDownloaded downloaded, $imgCached cached, '
    '$imgFailed failed → $imageAssetDir/',
  );
}

/// recipe.id → 安全文件名 slug（保留中文与字母数字，其余转 `_`）。
String _slug(String id) => id.replaceAll(RegExp(r'[^\w一-鿿]'), '_');

/// 从图片 URL 取受支持的扩展名（默认 .jpg）。
String _imageExt(String url) {
  final path = Uri.parse(url).path;
  final dot = path.lastIndexOf('.');
  final ext = dot == -1 ? '' : path.substring(dot).toLowerCase();
  const allowed = {'.jpg', '.jpeg', '.png', '.webp'};
  return allowed.contains(ext) ? ext : '.jpg';
}

/// 下载图片到 [out]；成功且非 LFS pointer（>1KB）才返回 true。
Future<bool> _downloadImage(HttpClient client, String url, File out) async {
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) return false;
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    if (bytes.length < 1000) return false; // 防 LFS pointer(131B)/错误页
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
    return true;
  } on Exception {
    return false;
  }
}

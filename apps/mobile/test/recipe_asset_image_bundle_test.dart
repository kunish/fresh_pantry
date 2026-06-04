import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 端到端验证「菜谱图片能显示」的根因闭环：
/// 上游成品图存于 Git LFS，jsDelivr/raw 端点只返回 131B 的 LFS pointer 文本而非真图，
/// 故改为构建期经 media 端点逐张下载、打包进 assets/recipes/images/，并把 howtocook.json
/// 的 imageUrl 改写为本地 asset 路径。本测试直接从 flutter_test 打包的 asset bundle 里
/// 读取并解码这些图，证明：(1) 含中文文件名的 asset 确实被正确打包、可加载；
/// (2) 字节是真图、能解码出非零尺寸的位图（而非 pointer 文本或 0 字节占位）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> decodeAsset(String key) async {
    final data = await rootBundle.load(key);
    final bytes = data.buffer.asUint8List();
    expect(
      bytes.length,
      greaterThan(1000),
      reason: '$key 应为真图（>1KB），而非 LFS pointer(131B)/空占位',
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  test('howtocook.json 的 asset 成品图能从 bundle 加载并解码（含中文文件名）', () async {
    final raw = await rootBundle.loadString('assets/recipes/howtocook.json');
    final recipes = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

    final assetUrls = recipes
        .map((r) => r['imageUrl'] as String?)
        .whereType<String>()
        .where((u) => u.startsWith('assets/recipes/images/'))
        .toList();

    // 现有数据应有相当数量的本地图；少于这个数说明导入/打包出了问题。
    expect(
      assetUrls.length,
      greaterThan(150),
      reason: 'imageUrl 指向本地 asset 的菜谱过少，疑似导入未生成图',
    );

    // 全量逐张确认 asset key 存在且为真图——一次性兜住任何漏打包/坏文件。
    for (final key in assetUrls) {
      final image = await decodeAsset(key);
      expect(image.width, greaterThan(0), reason: '$key 解码后宽度应 > 0');
      image.dispose();
    }
  });

  test('含括号中文文件名的图（冰粉/血浆鸭）打包并解码正常', () async {
    for (final key in const [
      'assets/recipes/images/howtocook_drink_冰粉_冰粉.jpg',
      'assets/recipes/images/howtocook_meat_dish_血浆鸭_血浆鸭.jpg',
    ]) {
      final image = await decodeAsset(key);
      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      image.dispose();
    }
  });
}

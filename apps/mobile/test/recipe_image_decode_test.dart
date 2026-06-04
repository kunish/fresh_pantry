import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/recipe_image.dart';

void main() {
  // 切 tab 闪白的根因:列表封面不传 width/height 时若解码全分辨率原图,几十张就
  // 撑爆 ImageCache 默认上限,切子 tab 重建时已解码的 completer 被驱逐 → 重新走
  // 异步首帧 → 闪。RecipeImage 用 LayoutBuilder 按渲染盒限制解码,锁定此不变量。
  testWidgets('列表封面按渲染盒限制解码尺寸,而非解码全分辨率原图', (tester) async {
    const url = 'https://example.com/cover.jpg';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 130,
              child: RecipeImage(
                imageSource: url,
                fallback: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    expect(
      provider,
      isA<ResizeImage>(),
      reason: '封面必须经 ResizeImage 限制解码尺寸,而不是裸 provider 解码原图',
    );
    final resize = provider as ResizeImage;
    final expectedWidth = (120 * tester.view.devicePixelRatio).round();
    expect(resize.width, expectedWidth, reason: '解码宽应为渲染盒宽 × DPR');
    expect(resize.imageProvider, isA<CachedNetworkImageProvider>());
    expect((resize.imageProvider as CachedNetworkImageProvider).url, url);
  });

  testWidgets('显式传入的 width/height 优先于布局约束决定解码尺寸', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: RecipeImage(
                imageSource: 'https://example.com/cover2.jpg',
                width: 80,
                height: 80,
                fallback: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final resize = image.image as ResizeImage;
    expect(resize.width, (80 * tester.view.devicePixelRatio).round());
  });

  testWidgets('assets/ 路径走 AssetImage（而非网络 provider），仍按渲染盒限制解码', (
    tester,
  ) async {
    const asset = 'assets/recipes/images/howtocook_staple_烙饼_烙饼.jpg';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 130,
              child: RecipeImage(imageSource: asset, fallback: SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final resize = image.image as ResizeImage;
    expect(resize.imageProvider, isA<AssetImage>());
    expect((resize.imageProvider as AssetImage).assetName, asset);
    expect(resize.width, (120 * tester.view.devicePixelRatio).round());
  });
}

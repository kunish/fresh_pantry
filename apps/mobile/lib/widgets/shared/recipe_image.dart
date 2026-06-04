import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class RecipeImage extends StatefulWidget {
  const RecipeImage({
    super.key,
    required this.imageSource,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.semanticLabel,
    this.cacheManager,
  });

  final String? imageSource;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? semanticLabel;

  /// 注入点:测试传入不触达 path_provider/sqflite 的桩缓存管理器;生产为 null,
  /// 使用 cached_network_image 的默认磁盘+内存缓存。
  final BaseCacheManager? cacheManager;

  @override
  State<RecipeImage> createState() => _RecipeImageState();
}

class _RecipeImageState extends State<RecipeImage> {
  String? _decodedDataSource;
  Uint8List? _decodedDataBytes;

  @override
  void didUpdateWidget(covariant RecipeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageSource != widget.imageSource) {
      _decodedDataSource = null;
      _decodedDataBytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.imageSource?.trim();
    if (source == null || source.isEmpty) {
      return widget.fallback;
    }
    // LayoutBuilder 拿到「实际渲染盒」,据此限制解码尺寸 —— 这是切 tab 不闪的关键:
    // 列表封面(recipe_card 等)不显式传 width/height,若解码 ~1600px 原图,几十张
    // 就撑爆全局 ImageCache(默认 100MB)→ 切子 tab 重建时已解码的 completer 被 LRU
    // 驱逐 → 重新走 MultiImageStreamCompleter 的异步首帧 → frameBuilder 先出一帧
    // fallback(「闪白」)。收口到渲染盒后每张只占几百 KB,封面长期驻留缓存,切 tab
    // 重建即命中、ImageCache 同步出帧(wasSynchronouslyLoaded)不闪。
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildImage(context, source, constraints),
    );
  }

  Widget _buildImage(
    BuildContext context,
    String source,
    BoxConstraints constraints,
  ) {
    // 解码尺寸优先用显式 width/height,否则回落到布局约束(按 DPR 缩放、取整稳定,
    // 避免 ImageCache key 抖动)。无界约束(罕见)时为 null,退回全分辨率解码。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final boxWidth =
        widget.width ??
        (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
    final boxHeight =
        widget.height ??
        (constraints.maxHeight.isFinite ? constraints.maxHeight : null);
    final cacheWidth = boxWidth != null && boxWidth > 0
        ? (boxWidth * dpr).round()
        : null;
    final cacheHeight = cacheWidth == null && boxHeight != null && boxHeight > 0
        ? (boxHeight * dpr).round()
        : null;

    if (_isDataImage(source)) {
      final bytes = _dataImageBytes(source);
      if (bytes == null) {
        return widget.fallback;
      }

      return Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        semanticLabel: widget.semanticLabel,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    }

    // 本地 asset(打包进 app 的菜谱图)走 AssetImage；其余视为远程 URL,走带磁盘缓存
    // 的 CachedNetworkImageProvider 喂给标准 Image(而非 CachedNetworkImage widget——
    // 后者每次重建都先渲染一帧 placeholder)。标准 Image 在 ImageCache 命中时同步出
    // 首帧,配合 gaplessPlayback,重建即时显示;只有冷加载(磁盘/网络)才回落到 fallback。
    final ImageProvider base = source.startsWith('assets/')
        ? AssetImage(source)
        : CachedNetworkImageProvider(source, cacheManager: widget.cacheManager);
    final provider = ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, base);
    return Image(
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      semanticLabel: widget.semanticLabel,
      errorBuilder: (_, _, _) => widget.fallback,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return widget.fallback;
      },
    );
  }

  Uint8List? _dataImageBytes(String source) {
    if (_decodedDataSource != source) {
      _decodedDataSource = source;
      _decodedDataBytes = _decodeDataImage(source);
    }
    return _decodedDataBytes;
  }
}

bool _isDataImage(String source) {
  return source.toLowerCase().startsWith('data:image/');
}

Uint8List? _decodeDataImage(String source) {
  const marker = ';base64,';
  final markerIndex = source.indexOf(marker);
  if (markerIndex == -1) {
    return null;
  }

  try {
    return base64Decode(source.substring(markerIndex + marker.length));
  } on FormatException {
    return null;
  }
}

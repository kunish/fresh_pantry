import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class RecipeImage extends StatelessWidget {
  const RecipeImage({
    super.key,
    required this.imageSource,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.semanticLabel,
  });

  final String? imageSource;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final source = imageSource?.trim();
    if (source == null || source.isEmpty) {
      return fallback;
    }

    if (_isDataImage(source)) {
      final bytes = _decodeDataImage(source);
      if (bytes == null) {
        return fallback;
      }

      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        semanticLabel: semanticLabel,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      semanticLabel: semanticLabel,
      errorBuilder: (_, _, _) => fallback,
    );
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

import 'package:flutter/material.dart';

import '../models/storage_area.dart';

/// 返回存储位置的中文显示名:fridge → '冰箱',pantry → '食品柜'。
String storageLabelFor(IconType storage) {
  switch (storage) {
    case IconType.fridge:
      return '冰箱';
    case IconType.pantry:
      return '食品柜';
  }
}

/// 返回存储位置的图标:fridge → Icons.kitchen,pantry → Icons.shelves。
IconData storageIconFor(IconType storage) {
  switch (storage) {
    case IconType.fridge:
      return Icons.kitchen;
    case IconType.pantry:
      return Icons.shelves;
  }
}

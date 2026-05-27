import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/utils/storage_labels.dart';

void main() {
  group('storageLabelFor', () {
    test('fridge → 冰箱', () {
      expect(storageLabelFor(IconType.fridge), '冰箱');
    });
    test('pantry → 食品柜', () {
      expect(storageLabelFor(IconType.pantry), '食品柜');
    });
  });
  group('storageIconFor', () {
    test('fridge → Icons.kitchen', () {
      expect(storageIconFor(IconType.fridge), Icons.kitchen);
    });
    test('pantry → Icons.shelves', () {
      expect(storageIconFor(IconType.pantry), Icons.shelves);
    });
  });
}

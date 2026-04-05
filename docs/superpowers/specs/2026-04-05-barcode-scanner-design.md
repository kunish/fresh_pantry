# Barcode Scanner Feature Design

## Overview

Add real barcode scanning functionality to the existing "快速扫描条码" placeholder in `AddIngredientScreen`. When a user taps the scanner area, the app opens a full-screen camera view, scans a barcode, queries the Open Food Facts API for product info, and auto-fills the add-ingredient form.

## User Flow

1. User taps the "快速扫描条码" card on the Add Ingredient screen.
2. App navigates to a full-screen barcode scanner screen with camera preview.
3. User points camera at a barcode (EAN-13, UPC-A, etc.).
4. On detection, the scanner screen shows a brief loading indicator.
5. App calls Open Food Facts API with the barcode.
6. **Success**: Returns to add-ingredient screen with name and category pre-filled. Shows SnackBar "已识别: {product_name}".
7. **Not found / Error**: Returns to add-ingredient screen with barcode number filled into the name field. Shows SnackBar "未找到商品信息，已填入条码号".
8. User reviews/edits the pre-filled form and saves as usual.

## Technical Design

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `mobile_scanner` | `^6.0.2` | Camera-based barcode scanning (Google MLKit) |
| `http` | `^1.2.2` | HTTP client for Open Food Facts API calls |

### New Files

#### `lib/services/open_food_facts_service.dart`

A stateless service class that queries the Open Food Facts API.

```dart
class OpenFoodFactsService {
  static const _baseUrl = 'https://world.openfoodfacts.org/api/v2/product';

  /// Returns a record (name, category) or null if not found.
  Future<({String name, String? category})?> lookupBarcode(String barcode) async;
}
```

- Endpoint: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=product_name,categories_tags`
- Timeout: 8 seconds
- On HTTP error or missing `product_name`: return `null`
- Category mapping: attempt to match `categories_tags` entries against the 5 known categories (`乳制品与蛋类`, `新鲜蔬果`, `食品柜常备`, `肉类与海鲜`, `香料与草本`) using a keyword map. If no match, return `null` for category.

Category keyword mapping:

| App Category | Open Food Facts keywords (substring match) |
|---|---|
| 乳制品与蛋类 | `dairy`, `milk`, `cheese`, `egg`, `yogurt`, `butter`, `cream` |
| 新鲜蔬果 | `fruit`, `vegetable`, `fresh`, `produce`, `salad` |
| 食品柜常备 | `cereal`, `pasta`, `rice`, `canned`, `snack`, `bread`, `flour`, `sugar`, `oil`, `sauce`, `condiment`, `beverage`, `drink`, `juice`, `coffee`, `tea` |
| 肉类与海鲜 | `meat`, `fish`, `seafood`, `chicken`, `pork`, `beef`, `poultry` |
| 香料与草本 | `spice`, `herb`, `seasoning`, `pepper`, `salt` |

#### `lib/screens/barcode_scanner_screen.dart`

Full-screen scanner page with:

- `MobileScanner` widget as the camera preview
- A semi-transparent overlay with a centered scan-window cutout (rounded rect)
- Header text "对准条码扫描" at top
- Close button (X) at top-left to cancel and go back
- On barcode detected: stop scanning, show centered `CircularProgressIndicator`, call `OpenFoodFactsService.lookupBarcode()`, then `Navigator.pop(context, result)`.
- The screen pops with a result record `({String name, String? category})` or `null` if cancelled.

### Modified Files

#### `pubspec.yaml`

Add `mobile_scanner: ^6.0.2` and `http: ^1.2.2` to dependencies.

#### `lib/screens/add_ingredient_screen.dart`

- Wrap `_buildBarcodeScanner()` content in a `GestureDetector` / `InkWell` with `onTap` that:
  1. `await Navigator.push()` to `BarcodeScannerScreen`
  2. If result is non-null, set `_nameController.text`, update `_selectedCategory` if category is provided
  3. Call `setState()` to refresh UI

#### `lib/models/ingredient.dart`

Add optional `barcode` field:
- `final String? barcode;` in constructor, `copyWith`, `toJson`, `fromJson`
- This enables future deduplication but is not required for MVP flow

### Platform Permissions

#### iOS (`ios/Runner/Info.plist`)

```xml
<key>NSCameraUsageDescription</key>
<string>需要使用相机来扫描食材条码</string>
```

#### Android

`mobile_scanner` auto-adds `CAMERA` permission via its own manifest. No manual changes needed.

### Error Handling

| Scenario | Behavior |
|---|---|
| Camera permission denied | `MobileScanner` shows built-in permission prompt; if denied, user sees message and can go back |
| Network error / timeout | Return `null` from service, fill barcode string into name field |
| API returns no product | Return `null` from service, fill barcode string into name field |
| API returns product without name | Return `null` from service, fill barcode string into name field |

### Testing

- `OpenFoodFactsService`: unit testable with mocked HTTP client (not required for MVP)
- `widget_test.dart`: no changes needed (scanner is behind a navigation push, not rendered in smoke test)
- Manual testing: scan a known product barcode (e.g., Coca-Cola EAN `5449000000996`)

## Out of Scope

- Barcode scan history
- Duplicate detection by barcode
- Offline barcode database
- Batch scanning (scan multiple items in succession)

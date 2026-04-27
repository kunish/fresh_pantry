# Remove Barcode Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove barcode scanning from the ingredient add flow while keeping name-based Open Food Facts image enrichment.

**Architecture:** Remove the scanner UI and scanner screen completely, then simplify the Open Food Facts service so it only supports name search. Keep manual ingredient entry, local smart defaults, and non-blocking image lookup unchanged.

**Tech Stack:** Flutter, Dart, Riverpod, SharedPreferences, Open Food Facts HTTP search API.

---

## File Structure

| File | Responsibility |
|---|---|
| `test/remove_barcode_feature_test.dart` | New widget tests proving the scanner card/copy is gone while add/dashboard screens still render. |
| `lib/screens/add_ingredient_screen.dart` | Remove scanner import, scanner action, scanner card, and scan-related SnackBars. Keep manual entry and name-based image lookup. |
| `lib/screens/dashboard_screen.dart` | Update quick action text so it no longer promises scanning. |
| `lib/services/open_food_facts_service.dart` | Remove barcode lookup and GTIN helpers. Keep only name-based search and shared HTTP/category helpers. |
| `lib/screens/barcode_scanner_screen.dart` | Delete the scanner screen. |
| `test/open_food_facts_service_test.dart` | Delete barcode-specific tests. |
| `pubspec.yaml` | Remove `mobile_scanner`; keep `http`. |
| `pubspec.lock` | Regenerate with `flutter pub get`. |

---

### Task 1: Add Failing UI Regression Tests

**Files:**
- Create: `test/remove_barcode_feature_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `test/remove_barcode_feature_test.dart` with this content:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/add_ingredient_screen.dart';
import 'package:fresh_pantry/screens/dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('add ingredient screen no longer shows barcode scanner entry', (
    tester,
  ) async {
    final prefs = await _prefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: AddIngredientScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('扫描条码'), findsNothing);
    expect(find.text('快速识别商品信息'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
    expect(find.text('食材名称'), findsOneWidget);
  });

  testWidgets('dashboard add action no longer mentions scanning', (
    tester,
  ) async {
    final prefs = await _prefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('扫码或手动录入'), findsNothing);
    expect(find.text('手动录入食材'), findsOneWidget);
  });
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({
    'inventory_items': '[]',
    'shopping_items': '[]',
    'add_history': '{}',
  });
  return SharedPreferences.getInstance();
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:

```bash
flutter test test/remove_barcode_feature_test.dart
```

Expected: FAIL because `AddIngredientScreen` still shows `扫描条码`, and `DashboardScreen` still shows `扫码或手动录入`.

- [ ] **Step 3: Conditional commit checkpoint**

If the user explicitly requested commits, run:

```bash
git add test/remove_barcode_feature_test.dart
git commit -m "test: cover barcode scanner removal"
```

If commits were not requested, skip this step.

---

### Task 2: Remove Scanner Entry Points From UI

**Files:**
- Modify: `lib/screens/add_ingredient_screen.dart`
- Modify: `lib/screens/dashboard_screen.dart`

- [ ] **Step 1: Remove the scanner import**

In `lib/screens/add_ingredient_screen.dart`, remove this import:

```dart
import 'barcode_scanner_screen.dart';
```

- [ ] **Step 2: Remove `_scanBarcode()`**

In `lib/screens/add_ingredient_screen.dart`, delete the whole `_scanBarcode()` method:

```dart
Future<void> _scanBarcode() async {
  final result = await Navigator.of(context).push<BarcodeResult>(
    MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
  );

  if (result == null || !mounted) return;

  if (result.category != null) {
    _nameController.text = result.productName;
    if (result.imageUrl != null) {
      _resolvedImageUrl = result.imageUrl!;
    }
    setState(() => _selectedCategory = result.category!);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已识别：${result.productName}'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  } else {
    _nameController.text = result.productName;
    if (result.imageUrl != null) {
      _resolvedImageUrl = result.imageUrl!;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('未找到商品信息，已填入条码号'),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Remove the scanner card from `build()`**

In `lib/screens/add_ingredient_screen.dart`, delete this block from the main `Column`:

```dart
// Barcode Scanner
_buildBarcodeScanner(),

const SizedBox(height: 28),
```

Keep the following `Ingredient Name` section directly after the frequent items section.

- [ ] **Step 4: Remove `_buildBarcodeScanner()`**

In `lib/screens/add_ingredient_screen.dart`, delete the whole `_buildBarcodeScanner()` method:

```dart
Widget _buildBarcodeScanner() {
  return GestureDetector(
    onTap: _scanBarcode,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryFixed,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.qr_code_scanner,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '扫描条码',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              Text(
                '快速识别商品信息',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 5: Update dashboard quick action copy**

In `lib/screens/dashboard_screen.dart`, change the add-ingredient quick action from:

```dart
subtitle: '扫码或手动录入',
semanticLabel: '添加新食材，扫码或手动录入',
```

to:

```dart
subtitle: '手动录入食材',
semanticLabel: '添加新食材，手动录入食材',
```

- [ ] **Step 6: Run the UI regression tests**

Run:

```bash
flutter test test/remove_barcode_feature_test.dart
```

Expected: PASS.

- [ ] **Step 7: Conditional commit checkpoint**

If the user explicitly requested commits, run:

```bash
git add lib/screens/add_ingredient_screen.dart lib/screens/dashboard_screen.dart test/remove_barcode_feature_test.dart
git commit -m "refactor: remove barcode scanner entry points"
```

If commits were not requested, skip this step.

---

### Task 3: Simplify Open Food Facts Service To Name Search Only

**Files:**
- Modify: `lib/services/open_food_facts_service.dart`
- Delete: `test/open_food_facts_service_test.dart`

- [ ] **Step 1: Replace the barcode result model with a name-search result model**

In `lib/services/open_food_facts_service.dart`, replace:

```dart
/// Result returned from barcode lookup.
class BarcodeResult {
  final String productName;
  final String? category;
  final String barcode;
  final String? imageUrl;

  const BarcodeResult({
    required this.productName,
    required this.barcode,
    this.category,
    this.imageUrl,
  });
}
```

with:

```dart
/// Result returned from Open Food Facts name search.
class FoodSearchResult {
  final String productName;
  final String? category;
  final String? imageUrl;

  const FoodSearchResult({
    required this.productName,
    this.category,
    this.imageUrl,
  });
}
```

- [ ] **Step 2: Remove barcode constants and helpers**

In `lib/services/open_food_facts_service.dart`, remove:

```dart
static const _baseUrl = 'https://world.openfoodfacts.org/api/v2/product';
static const _productBarcodeLengths = <int>{8, 12, 13, 14};

static final _nonDigitRegex = RegExp(r'[^0-9]');
```

Also delete these methods:

```dart
static String? normalizeProductBarcode(String rawBarcode) { ... }
static String? findProductBarcode(Iterable<String?> rawBarcodes) { ... }
static Future<BarcodeResult?> lookup(String barcode) async { ... }
static bool _hasValidGtinCheckDigit(String digits) { ... }
```

- [ ] **Step 3: Update `searchByName()` signature and return object**

In `lib/services/open_food_facts_service.dart`, change:

```dart
static Future<BarcodeResult?> searchByName(String name) async {
```

to:

```dart
static Future<FoodSearchResult?> searchByName(String name) async {
```

Change the search fields from:

```dart
'&fields=product_name,categories_tags,image_front_small_url,code',
```

to:

```dart
'&fields=product_name,categories_tags,image_front_small_url',
```

Remove:

```dart
final code = product['code']?.toString() ?? '';
```

Replace the return block with:

```dart
return FoodSearchResult(
  productName: productName.trim(),
  category: category,
  imageUrl: imageUrl,
);
```

- [ ] **Step 4: Delete barcode service tests**

Delete `test/open_food_facts_service_test.dart` because it only asserts barcode validation behavior that no longer exists.

- [ ] **Step 5: Run analysis for service and add screen**

Run:

```bash
flutter analyze lib/services/open_food_facts_service.dart lib/screens/add_ingredient_screen.dart
```

Expected: no `BarcodeResult`, `lookup`, `normalizeProductBarcode`, or `findProductBarcode` reference errors.

- [ ] **Step 6: Conditional commit checkpoint**

If the user explicitly requested commits, run:

```bash
git add lib/services/open_food_facts_service.dart test/open_food_facts_service_test.dart
git commit -m "refactor: remove barcode lookup from Open Food Facts service"
```

If commits were not requested, skip this step.

---

### Task 4: Delete Scanner Screen And Dependency

**Files:**
- Delete: `lib/screens/barcode_scanner_screen.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

- [ ] **Step 1: Delete scanner screen file**

Delete:

```text
lib/screens/barcode_scanner_screen.dart
```

- [ ] **Step 2: Remove `mobile_scanner` from dependencies**

In `pubspec.yaml`, change:

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.2.1
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^2.6.1
  shared_preferences: ^2.3.4
  mobile_scanner: ^7.2.0
  http: ^1.2.2
```

to:

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.2.1
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^2.6.1
  shared_preferences: ^2.3.4
  http: ^1.2.2
```

- [ ] **Step 3: Regenerate lockfile**

Run:

```bash
flutter pub get
```

Expected: `pubspec.lock` no longer includes `mobile_scanner` or its plugin transitive entries that are only required by scanner support.

- [ ] **Step 4: Search for remaining barcode scanner references**

Run:

```bash
rg "barcode|Barcode|mobile_scanner|qr_code_scanner|BarcodeScannerScreen|扫描条码|扫码" lib test pubspec.yaml
```

Expected: no matches related to scanner UI, scanner page, or scanner dependency. Matches for `Ingredient.barcode` are acceptable only in `lib/models/ingredient.dart` because persisted-data compatibility keeps that field.

- [ ] **Step 5: Conditional commit checkpoint**

If the user explicitly requested commits, run:

```bash
git add lib/screens/barcode_scanner_screen.dart pubspec.yaml pubspec.lock
git commit -m "refactor: remove barcode scanner dependency"
```

If commits were not requested, skip this step.

---

### Task 5: Full Verification

**Files:**
- Verify repository state only.

- [ ] **Step 1: Run full test suite**

Run:

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 2: Run full static analysis**

Run:

```bash
flutter analyze
```

Expected: no issues found.

- [ ] **Step 3: Verify dependency cleanup**

Run:

```bash
flutter pub deps | rg "mobile_scanner" || true
```

Expected: no output.

- [ ] **Step 4: Manual verification checklist**

Open the app and verify:

- Add ingredient screen has no scanner card.
- Dashboard add action says `手动录入食材`.
- Typing `牛奶` still shows smart defaults.
- Saving a manually entered ingredient still adds it to inventory.

- [ ] **Step 5: Conditional final commit**

If the user explicitly requested commits, run:

```bash
git add lib test pubspec.yaml pubspec.lock
git commit -m "refactor: remove barcode scanning feature"
```

If commits were not requested, skip this step.

---

## Self-Review

- Spec coverage: The plan removes scanner UI, scanner screen, barcode lookup helpers, barcode tests, scanner dependency, and scan-oriented copy while preserving manual entry, `Ingredient.barcode`, `http`, and name-based image lookup.
- Red-flag scan: No task contains unresolved implementation gaps or open-ended instructions.
- Type consistency: `FoodSearchResult` replaces `BarcodeResult` only inside the Open Food Facts name-search path; `AddIngredientScreen` uses inferred result typing, so only `.imageUrl` access remains required there.

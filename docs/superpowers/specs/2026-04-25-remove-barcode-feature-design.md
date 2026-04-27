# Remove Barcode Feature Design

## Goal

Remove barcode scanning from the add-ingredient flow because product lookup by barcode is unreliable for this app's target use. Keep the existing Open Food Facts name-based image enrichment so manually entered ingredient names can still resolve a product image when available.

## Scope

Remove:

- The barcode scanner card from `AddIngredientScreen`.
- The full-screen barcode scanner page.
- Barcode lookup, barcode normalization, and product-barcode selection helpers from `OpenFoodFactsService`.
- The `mobile_scanner` dependency and generated lockfile entries.
- Barcode-specific tests.
- UI copy that promises scanning, such as dashboard text that says users can scan or manually enter ingredients.

Keep:

- Manual ingredient entry.
- Smart defaults from `FoodKnowledge`.
- Open Food Facts name-based lookup via `searchByName()` for image enrichment.
- The `http` dependency because API-based image enrichment still uses it.
- The existing optional `Ingredient.barcode` model field for stored-data compatibility. Existing saved data may contain this field, and removing it would not improve the user-facing flow.

## User Flow

The add-ingredient screen will start with frequent items, then the ingredient name field. Users add ingredients manually. When the name matches local food knowledge, the app continues to fill category, storage, and shelf-life defaults. When possible, the app also looks up an image by name through Open Food Facts.

No scanner screen opens, and no UI suggests barcode scanning is available.

## Code Changes

### `lib/screens/add_ingredient_screen.dart`

- Remove the import of `barcode_scanner_screen.dart`.
- Remove `_scanBarcode()`.
- Remove `_buildBarcodeScanner()`.
- Remove the barcode scanner card from `build()`.
- Keep `_lookupImage()` and `_resolvedImageUrl` because image enrichment still applies to manual input and frequent item selection.

### `lib/screens/barcode_scanner_screen.dart`

Delete this file. No code should import it after the add screen is updated.

### `lib/services/open_food_facts_service.dart`

- Remove barcode-only API pieces: `lookup()`, `normalizeProductBarcode()`, `findProductBarcode()`, and GTIN check-digit helpers.
- Keep `searchByName()` and its small result object so add flow image lookup remains unchanged.
- Keep HTTP timeout, retry, headers, category mapping, and safe JSON parsing helpers used by `searchByName()`.

### `pubspec.yaml` and `pubspec.lock`

Remove `mobile_scanner`. Keep `http`.

### Tests

Delete or rewrite barcode-specific tests. The remaining service behavior should not assert barcode validation. If a test remains, it should cover name-based lookup helpers only if that can be done without live network dependency.

### Copy

Change dashboard/add-entry copy from scan-oriented wording to manual-entry wording. For example, `扫码或手动录入` should become `手动录入食材`.

## Error Handling

There is no barcode error path after removal. Name-based image lookup remains non-blocking: if the API fails or no image is found, the ingredient is still saved with an empty image URL and existing UI fallbacks apply.

## Testing

Run:

```bash
flutter pub get
flutter test
flutter analyze
```

Manual verification:

- Add ingredient screen has no scan card.
- Dashboard copy no longer mentions scanning.
- Typing a known ingredient still fills local defaults.
- Saving an ingredient still works.

## Out Of Scope

- Removing Open Food Facts name search.
- Removing `Ingredient.barcode` from persisted data.
- Replacing barcode scanning with another product catalog provider.
- Redesigning the add-ingredient screen beyond removing the scanner entry point.

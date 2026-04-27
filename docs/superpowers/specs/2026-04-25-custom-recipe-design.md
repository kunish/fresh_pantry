# Custom Recipe Design

## Context

Fresh Pantry currently shows recipe recommendations from mock data and TheMealDB, with details rendered through `RecipeDetailScreen`. Users need a first-party way to save their own recipes locally, manage them, and open them from a dedicated "我的食谱" list.

## Goals

- Add a clear homepage quick-action entry for custom recipes.
- Support local custom recipe creation, viewing, editing, and deletion.
- Persist custom recipes with `SharedPreferences`.
- Reuse the existing `Recipe` model and detail screen where practical.
- Keep custom recipes separate from inventory-based recommendations in this first version.

## Non-Goals

- Custom recipes will not participate in `recommendedRecipesProvider` ranking in this version.
- No image URL, tags, inventory picker, or automatic recipe generation in the first version.
- No cloud sync or account-level recipe storage.

## Product Flow

The dashboard quick actions will include a new "添加食谱" action. Tapping it opens `MyRecipesScreen`, a dedicated list for locally saved recipes.

`MyRecipesScreen` will show:

- An empty state when there are no custom recipes.
- A primary add button for creating a recipe.
- Recipe cards for saved custom recipes.
- Entry points to view details, edit, and delete each custom recipe.

Creating and editing share one screen, `CustomRecipeFormScreen`. Viewing uses the existing `RecipeDetailScreen`, with management actions exposed for custom recipes.

## Data Model

Use the existing `Recipe` and `RecipeIngredient` models:

- `id`: generated as `custom_<timestamp>` when creating a recipe.
- `name`: required.
- `category`: required, defaulting to `家常`.
- `difficulty`: required integer from 1 to 5.
- `cookingMinutes`: required positive integer.
- `description`: optional.
- `ingredients`: at least one item, each with required `name` and `amount`.
- `steps`: at least one non-empty step.

Editing preserves the existing recipe ID and replaces the editable fields.

## State And Persistence

Add `customRecipesProvider`, implemented with a notifier that reads and writes a JSON list under a `SharedPreferences` key such as `custom_recipes`.

The notifier exposes:

- `add(Recipe recipe)`
- `update(String id, Recipe recipe)`
- `remove(String id)`

Persistence should be defensive. Corrupt saved JSON should not crash the app; it should fall back to an empty custom recipe list.

## UI Behavior

`DashboardScreen` adds a third quick action or reshapes the current quick-action area to include "添加食谱" without replacing "添加新食材" or "购物清单".

`MyRecipesScreen` uses existing visual language from dashboard and recipe cards. Cards show recipe name, description, cooking time, and ingredient count. Selecting a card opens `RecipeDetailScreen`.

`CustomRecipeFormScreen` validates on save. If validation fails, it shows inline or snackbar feedback and does not persist.

Deletion requires confirmation before removing the recipe.

## Error Handling

- Invalid persisted JSON returns an empty list.
- Invalid form fields block save with user-visible feedback.
- Updating or deleting a missing recipe ID is a no-op.

## Testing

Provider tests should cover:

- Loading an empty custom recipe list.
- Adding a recipe persists it.
- Updating a recipe preserves ID and changes fields.
- Removing a recipe persists removal.
- Malformed persisted JSON does not throw.

Widget tests should cover:

- Dashboard quick action opens `MyRecipesScreen`.
- Empty custom recipe list renders an empty state.
- A saved recipe appears in the list and opens detail.
- Form validation blocks missing required fields.

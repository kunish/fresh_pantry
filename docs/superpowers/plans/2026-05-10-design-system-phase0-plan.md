# Design System Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish single source of truth design system documentation (`docs/design-system.md`) and align `lib/theme/app_theme.dart` + `lib/theme/app_typography.dart` with the recipe form implementation language. No widget/screen changes.

**Architecture:** Three small TDD-driven theme adjustments (1-line/few-line each) lock down phase 0's code contract. The bulk of work is writing a 5-section design system document (L1 Tokens / L2 Themes / L3 Component Patterns / L4 Page Patterns / L5 Interaction Patterns) where 21 entries are completely described and 11 are placeholders for later phases.

**Tech Stack:** Dart 3.7 / Flutter, `flutter_test`, markdown.

**Spec:** [`docs/superpowers/specs/2026-05-10-design-system-phase0-design.md`](../specs/2026-05-10-design-system-phase0-design.md)

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Modify | `lib/theme/app_typography.dart` | Add `AppTypography.sectionTitle` getter |
| Modify | `lib/theme/app_theme.dart` | Update `cardTheme` (16/lowest/border) and `chipTheme` (low) |
| Modify | `test/app_theme_tokens_test.dart` | Add three new groups locking new theme/typography contract |
| Create | `docs/design-system.md` | The phase 0 deliverable: 800-line design system documentation |

---

## Task 1: Add `AppTypography.sectionTitle` getter

**Files:**
- Modify: `lib/theme/app_typography.dart`
- Modify: `test/app_theme_tokens_test.dart`

- [ ] **Step 1.1: Add failing test for sectionTitle**

In `test/app_theme_tokens_test.dart`, ensure these imports exist at the top (add what's missing):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_radius.dart';
import 'package:fresh_pantry/theme/app_spacing.dart';
import 'package:fresh_pantry/theme/app_typography.dart';
```

Then add this group at the bottom of `void main() { ... }`, after the existing `AppRadius tokens` group:

```dart
  group('AppTypography.sectionTitle', () {
    test('is titleMedium with FontWeight.w800, same family and size', () {
      final sectionTitle = AppTypography.sectionTitle;
      final titleMedium = AppTypography.textTheme.titleMedium!;
      expect(sectionTitle.fontWeight, FontWeight.w800);
      expect(sectionTitle.fontSize, titleMedium.fontSize);
      expect(sectionTitle.fontFamily, titleMedium.fontFamily);
    });
  });
```

- [ ] **Step 1.2: Run test, expect fail**

```bash
flutter test test/app_theme_tokens_test.dart
```

Expected: FAIL with `The getter 'sectionTitle' isn't defined for the type 'AppTypography'.` (or compile error).

- [ ] **Step 1.3: Add `sectionTitle` getter**

In `lib/theme/app_typography.dart`, add this getter inside `class AppTypography` (after the existing `textTheme` getter, before the closing `}`):

```dart
  static TextStyle get sectionTitle =>
      textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800);
```

(No new comment — the spec doc explains the use case; in-code dartdoc would duplicate.)

- [ ] **Step 1.4: Run test, expect pass**

```bash
flutter test test/app_theme_tokens_test.dart
```

Expected: PASS, all groups green.

- [ ] **Step 1.5: Commit**

```bash
git add lib/theme/app_typography.dart test/app_theme_tokens_test.dart
git commit -m "feat(theme): add AppTypography.sectionTitle (titleMedium + w800)"
```

---

## Task 2: Align `cardTheme` to recipe form spec

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Modify: `test/app_theme_tokens_test.dart`

- [ ] **Step 2.1: Add failing tests for cardTheme**

Add these imports to `test/app_theme_tokens_test.dart` if not already present:

```dart
import 'package:fresh_pantry/theme/app_colors.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
```

Add this group at the bottom of `void main()`:

```dart
  group('AppTheme cardTheme', () {
    final cardTheme = AppTheme.lightTheme.cardTheme;

    test('elevation is 0 (flat surfaces by design)', () {
      expect(cardTheme.elevation, 0);
    });

    test('uses AppRadius.lg (16) and 1px outlineVariant border', () {
      final shape = cardTheme.shape as RoundedRectangleBorder;
      final radius = (shape.borderRadius as BorderRadius).topLeft.x;
      expect(radius, AppRadius.lg);
      expect(shape.side.color, AppColors.outlineVariant);
      expect(shape.side.width, 1);
    });

    test('uses surfaceContainerLowest as default color', () {
      expect(cardTheme.color, AppColors.surfaceContainerLowest);
    });
  });
```

- [ ] **Step 2.2: Run tests, expect fail**

```bash
flutter test test/app_theme_tokens_test.dart
```

Expected: FAIL on radius (currently 24), color (currently surfaceContainer), and shape side (currently no border).

- [ ] **Step 2.3: Update `cardTheme` in `app_theme.dart`**

In `lib/theme/app_theme.dart`, find the existing `cardTheme:` block (lines 75-80):

```dart
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: AppColors.surfaceContainer,
        margin: EdgeInsets.zero,
      ),
```

Replace with:

```dart
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.outlineVariant),
        ),
        color: AppColors.surfaceContainerLowest,
        margin: EdgeInsets.zero,
      ),
```

- [ ] **Step 2.4: Run tests, expect pass**

```bash
flutter test test/app_theme_tokens_test.dart
```

Expected: PASS, all groups green.

- [ ] **Step 2.5: Commit**

```bash
git add lib/theme/app_theme.dart test/app_theme_tokens_test.dart
git commit -m "feat(theme): align cardTheme with recipe form (16/lowest/1px outlineVariant)"
```

---

## Task 3: Align `chipTheme` to recipe form spec

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Modify: `test/app_theme_tokens_test.dart`

- [ ] **Step 3.1: Add failing test for chipTheme**

Add this group to `test/app_theme_tokens_test.dart` (below the cardTheme group):

```dart
  group('AppTheme chipTheme', () {
    final chipTheme = AppTheme.lightTheme.chipTheme;

    test('uses surfaceContainerLow as default backgroundColor', () {
      expect(chipTheme.backgroundColor, AppColors.surfaceContainerLow);
    });

    test('uses primary as selectedColor', () {
      expect(chipTheme.selectedColor, AppColors.primary);
    });

    test('uses StadiumBorder shape', () {
      expect(chipTheme.shape, isA<StadiumBorder>());
    });
  });
```

- [ ] **Step 3.2: Run tests, expect fail**

```bash
flutter test test/app_theme_tokens_test.dart
```

Expected: FAIL on `backgroundColor` (currently `surfaceContainerHigh`).

- [ ] **Step 3.3: Update `chipTheme.backgroundColor` in `app_theme.dart`**

In `lib/theme/app_theme.dart`, find the existing `chipTheme:` block. Change the line:

```dart
        backgroundColor: AppColors.surfaceContainerHigh,
```

to:

```dart
        backgroundColor: AppColors.surfaceContainerLow,
```

(No other line in the chipTheme block changes.)

- [ ] **Step 3.4: Run tests, expect pass**

```bash
flutter test test/app_theme_tokens_test.dart
```

Expected: PASS.

- [ ] **Step 3.5: Commit**

```bash
git add lib/theme/app_theme.dart test/app_theme_tokens_test.dart
git commit -m "feat(theme): align chipTheme backgroundColor with PillChip default"
```

---

## Task 4: Create `docs/design-system.md` with skeleton + header

**Files:**
- Create: `docs/design-system.md`

- [ ] **Step 4.1: Create file with skeleton**

Create `docs/design-system.md` with the following content (sections will be filled in tasks 5-9):

````markdown
# Fresh Pantry Design System

**Status**: Draft (phase 0 establishing baseline)
**Last updated**: 2026-05-10
**Source of truth**: This document. The recipe form widgets (`lib/widgets/recipe_form/`) are the **reference implementation** of the visual language described here.

> **About `design/html/` and `design/screenshots/`**: those are 2026-04-27 early external mockups covering dashboard / inventory / add_ingredient / shopping_list (search states included), but not recipe form. They are **deprecated** and no longer source of truth — kept only for historical reference. When this document and an old HTML mock disagree, **this document wins**.

---

## How to read this document

The design system is organized in 5 layers, from primitive to composite:

1. **L1 Tokens** — design primitives (color / spacing / radius / typography scales)
2. **L2 Themes** — Material `ThemeData` configuration that wires tokens to component themes
3. **L3 Component Patterns** — reusable UI patterns expressed as use cases (e.g. "horizontal multi-select with presets")
4. **L4 Page Patterns** — screen-level conventions (scaffold, AppBar, navigation, padding)
5. **L5 Interaction Patterns** — runtime feedback patterns (SnackBar, loading, empty state, dialogs)

Each entry includes:
- a short definition,
- references to the relevant token(s) or theme key(s),
- the **reference implementation path** (a file/widget that demonstrates the pattern),
- usage rules (when to use, when not to use).

Entries marked **(Placeholder)** are intentionally undecided — they will be filled in as later phases reach the relevant code paths. Each placeholder names the phase responsible for filling it in.

---

## L1 Tokens

> Filled in Task 5.

## L2 Themes

> Filled in Task 6.

## L3 Component Patterns

> Filled in Task 7.

## L4 Page Patterns

> Filled in Task 8.

## L5 Interaction Patterns

> Filled in Task 9.

---

## Appendix A: Transient Inconsistencies

> Filled in Task 9.

## Appendix B: Decision Log

> Filled in Task 9.
````

- [ ] **Step 4.2: Verify file exists and renders**

```bash
ls -la docs/design-system.md
wc -l docs/design-system.md
```

Expected: file exists, ~60 lines.

- [ ] **Step 4.3: Commit**

```bash
git add docs/design-system.md
git commit -m "docs(design-system): create skeleton with L1-L5 + appendix scaffolding"
```

---

## Task 5: Fill L1 Tokens section (4 entries)

**Files:**
- Modify: `docs/design-system.md`

- [ ] **Step 5.1: Replace L1 placeholder with full content**

In `docs/design-system.md`, replace the line `> Filled in Task 5.` (under `## L1 Tokens`) with the following content:

````markdown
### 1.1 Color

**Definition**: Project color palette, derived from a green-forward food/freshness brand.
**Source**: [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart) (`AppColors`).

The palette has four functional families plus a 9-step surface scale:

- **Primary** — `primary` (`#0F5238`), `primaryContainer`, `primaryFixed`. Brand green; used for FAB, active states, primary buttons.
- **Secondary** — `secondary` (`#9B4500`), `secondaryContainer` (`#FC8A40`), `secondaryFixed`. Burnt-orange accent; used for warnings, urgency badges.
- **Tertiary** — `tertiary` / `tertiaryContainer` / `tertiaryFixedDim`. Muted gold; used sparingly for tier-3 accents (curators tip, etc.).
- **Error** — `error` / `errorContainer` family. Validation, destructive actions.
- **Surface scale** — 9 levels from `surfaceContainerLowest` (white, `#FFFFFF`) to `surfaceContainerHighest` (`#E5E2DF`); plus `surface` / `surfaceBright` (`#FCF9F6`) and `surfaceDim`.

**AI accent** — `aiAccent` aliases to `primary`; `aiGradientStart`/`aiGradientEnd` are derived from primary green. AI visuals stay in the brand color family rather than introducing a new hue.

**Hard rule**: never hard-code hex values outside `AppColors`. If a needed shade is missing, add it to `AppColors` first.

### 1.2 Spacing

**Definition**: 8-step spacing scale.
**Source**: [`lib/theme/app_spacing.dart`](../lib/theme/app_spacing.dart) (`AppSpacing`).

| Token | px | Use |
|---|---|---|
| `xs` | 4 | tight gaps inside compact rows |
| `sm` | 8 | gap between intra-element parts |
| `md` | 12 | gap between sibling elements |
| `lg` | 16 | gap between paragraphs in a section |
| `xl` | 20 | section-edge padding |
| `xxl` | 24 | screen horizontal padding (most common) |
| `xxxl` | 28 | (rare) extra-large screen padding |
| `huge` | 32 | hero spacing |

**Hard rule**: do not use raw `EdgeInsets.all(16)` etc.; always reference `AppSpacing`.

### 1.3 Radius

**Definition**: 7-step border-radius scale.
**Source**: [`lib/theme/app_radius.dart`](../lib/theme/app_radius.dart) (`AppRadius`).

| Token | px | Use |
|---|---|---|
| `xs` | 4 | thin separator caps |
| `sm` | 8 | small inset elements (icon backplates, badges) |
| `md` | 12 | default surface (snackbar, banner) |
| `lg` | 16 | **default card radius** (see L2.1) |
| `xl` | 20 | dialog / modal sheet |
| `xxl` | 24 | large hero card |
| `pill` | 999 | stadium / pill shape (chip, FAB) |

### 1.4 Typography

**Definition**: 13-style type scale + one named-pattern token (`sectionTitle`).
**Source**: [`lib/theme/app_typography.dart`](../lib/theme/app_typography.dart) (`AppTypography`).

The base scale is exposed via `AppTypography.textTheme` (a `Material 3 TextTheme`), with two font families:

- **Plus Jakarta Sans** (`displayLarge` ... `titleLarge`) — display/headline weight 700–800.
- **Manrope** (`titleMedium` ... `labelSmall`) — body/label weight 400–700.

| Style | Family | Size | Weight | Use |
|---|---|---|---|---|
| `displayLarge/Medium/Small` | Jakarta | 32/28/24 | w800 | hero numbers (rare) |
| `headlineLarge/Medium/Small` | Jakarta | 28/24/20 | w700 | screen titles |
| `titleLarge` | Jakarta | 20 | w600 | section titles (large) |
| `titleMedium` | Manrope | 16 | w600 | section titles (default) |
| `titleSmall` | Manrope | 14 | w600 | sub-section titles |
| `bodyLarge/Medium/Small` | Manrope | 16/14/12 | w400 | running text |
| `labelLarge/Medium/Small` | Manrope | 14/12/11 | w700/w600/w600 | chip labels, captions, tags |

**Named-pattern token**:

| Token | Derivation | Use |
|---|---|---|
| `sectionTitle` | `titleMedium.copyWith(fontWeight: w800)` | bold "section card" titles inside `RecipeFormCard`-style surfaces |

**Hard rule**: do not pass raw `fontSize` numbers (e.g., `fontSize: 13`) outside `AppTypography`. If a missing weight/size is needed, derive a named token in `AppTypography` first.

````

- [ ] **Step 5.2: Verify section line count**

```bash
awk '/^## L1 Tokens/,/^## L2 Themes/' docs/design-system.md | wc -l
```

Expected: roughly 70-90 lines (4 entries with tables).

- [ ] **Step 5.3: Commit**

```bash
git add docs/design-system.md
git commit -m "docs(design-system): fill L1 Tokens (color/spacing/radius/typography)"
```

---

## Task 6: Fill L2 Themes section (5 entries)

**Files:**
- Modify: `docs/design-system.md`

- [ ] **Step 6.1: Replace L2 placeholder with full content**

In `docs/design-system.md`, replace the line `> Filled in Task 6.` (under `## L2 Themes`) with:

````markdown
> All theme configuration lives in [`lib/theme/app_theme.dart`](../lib/theme/app_theme.dart). The theme is wired via Material 3 (`useMaterial3: true`) with a custom `ColorScheme` derived from `AppColors`.

### 2.1 Card

**Theme key**: `ThemeData.cardTheme`.
**Reference implementation**: [`RecipeFormCard`](../lib/widgets/recipe_form/recipe_form_card.dart) (note: currently a `Container`-based reimplementation that bypasses the theme — see Appendix A T2; new code should use `Card` to inherit the theme).

| Property | Value | Token |
|---|---|---|
| Elevation | 0 | — (flat surfaces by design) |
| Radius | 16 | `AppRadius.lg` |
| Background color | white (`#FFFFFF`) | `AppColors.surfaceContainerLowest` |
| Border | 1px outlineVariant | `AppColors.outlineVariant` |
| Margin | zero | — |

**Error state**: when a card represents a form section with validation errors, override the border to `1.5px AppColors.error` (consumer responsibility — see L3.6).

**When to use**: any "section grouping" surface — form sections, list items, info panels.

**When NOT to use**: full-bleed hero imagery (use a different container — see L3.5 reference if applicable); inline pills or chips (use `PillChip` — L3.10).

### 2.2 Chip

**Theme key**: `ThemeData.chipTheme` (fallback for any future Material `Chip(...)` use).
**Reference implementation**: [`PillChip`](../lib/widgets/shared/pill_chip.dart) — the project's **only** chip implementation.

| Property | Value | Token |
|---|---|---|
| Shape | StadiumBorder (full pill) | `AppRadius.pill` |
| Default background | surfaceContainerLow | `AppColors.surfaceContainerLow` |
| Selected color | primary | `AppColors.primary` |
| Label style | labelLarge (14/w700) | `AppTypography.textTheme.labelLarge` |
| Show checkmark | false | — |
| Side | none | — |

**Contrast caveat**: when a chip is placed on top of a white card (`surfaceContainerLowest`), the default `surfaceContainerLow` (`#F6F3F0`) only has subtle contrast. In that context, the consumer should pass `backgroundColor: AppColors.surfaceContainer` to PillChip explicitly for stronger separation.

**Implementation rule**: new chip surfaces must use `PillChip`, not Material's `Chip` / `FilterChip` / `ChoiceChip`. The chipTheme exists only as fallback — it is currently unused (zero `Chip(...)` call sites in `lib/`).

### 2.3 InputDecoration

**Theme key**: `ThemeData.inputDecorationTheme`.
**Reference implementation**: text fields in [`custom_recipe_form_screen.dart`](../lib/screens/custom_recipe_form_screen.dart).

| Property | Value | Token |
|---|---|---|
| Filled | true | — |
| Fill color | surfaceContainerHigh | `AppColors.surfaceContainerHigh` |
| Default radius | 16 | (literal `BorderRadius.circular(16)`) |
| Default border | none | `BorderSide.none` |
| Focus border | primary 1.5px | `AppColors.primary`, width `1.5` |
| Content padding | 16h × 14v | (literal `EdgeInsets.symmetric(horizontal: 16, vertical: 14)`) |

**Error state**: `errorText: ...` triggers default Material error styling; do not customize it per-field (see L3.6).

### 2.4 Buttons

**Theme keys**: `filledButtonTheme`, `textButtonTheme`.

| Variant | Shape | Padding |
|---|---|---|
| FilledButton | StadiumBorder | 24h × 16v |
| TextButton | StadiumBorder | (default) |

**Selection rule**: `FilledButton` for primary actions ("Save Recipe", "Add Ingredient"). `TextButton` for secondary inline actions ("Discard", "Cancel"). For destructive actions, use a `FilledButton` with explicit `style: FilledButton.styleFrom(backgroundColor: AppColors.error)` — there is no separate "destructiveButton" theme.

### 2.5 AppBar / Scaffold

**Theme keys**: `appBarTheme`, `scaffoldBackgroundColor`.
**Reference implementation**: [`TopAppBar`](../lib/widgets/common/top_app_bar.dart) (custom widget for main 4 screens); Material `AppBar` for pushed screens (recipe form, ingredient detail, etc.).

| Property | Value |
|---|---|
| Scaffold background | `AppColors.surface` (`#FCF9F6`) |
| AppBar background | `Colors.transparent` |
| Elevation | 0 |
| `scrolledUnderElevation` | 0 (no surface tint when scrolled) |
| `systemOverlayStyle` | `kAppSystemOverlayStyle` (defined in `app_theme.dart`, also wired at app root via `AnnotatedRegion`) |

**System overlay rule**: `kAppSystemOverlayStyle` is wired both at app root (`FreshPantryApp.build`) and on `AppBarTheme` — both are required, otherwise pushed screens override the root and break status bar contrast.

````

- [ ] **Step 6.2: Verify section line count**

```bash
awk '/^## L2 Themes/,/^## L3 Component Patterns/' docs/design-system.md | wc -l
```

Expected: roughly 90-110 lines.

- [ ] **Step 6.3: Commit**

```bash
git add docs/design-system.md
git commit -m "docs(design-system): fill L2 Themes (card/chip/input/button/appbar)"
```

---

## Task 7: Fill L3 Component Patterns section (10 entries: 9 complete + 1 placeholder)

**Files:**
- Modify: `docs/design-system.md`

- [ ] **Step 7.1: Replace L3 placeholder with full content**

In `docs/design-system.md`, replace the line `> Filled in Task 7.` (under `## L3 Component Patterns`) with the content below. Each entry follows the format: heading, definition, reference implementation, decision rules, then optional caveats.

````markdown
### 3.1 Section Card

**Use case**: visually group a labeled section of related controls (a form section, a settings group, etc.).
**Reference implementation**: [`RecipeFormCard`](../lib/widgets/recipe_form/recipe_form_card.dart).

**Anatomy**:
- Outer container: matches L2.1 Card (16 radius, surfaceContainerLowest, 1px outlineVariant border).
- Header row (top of card): 30×30 colored icon backplate (default `AppColors.primaryFixed` with `AppColors.primary` icon at 18px), then bold section title (`AppTypography.sectionTitle`), then optional pill-shaped count badge on the right.
- Body: arbitrary child, 12px gap below header.

**When to use**: form sections (recipe details / basic info / ingredients), settings groups.

**When NOT to use**: list items (use a tighter row layout); full-screen surfaces (use Scaffold directly).

### 3.2 Horizontal Multi-Select (Presets)

**Use case**: pick one value from a small fixed set of frequently-used presets, where the set is short and order matters.
**Reference implementation**: [`CookingTimeRow`](../lib/widgets/recipe_form/cooking_time_row.dart) using [`PillChip`](../lib/widgets/shared/pill_chip.dart).

**Anatomy**:
- Horizontal `ListView.separated` of `PillChip` (height 36, separator `AppSpacing.sm`).
- Selected chip: `selectedBackgroundColor: AppColors.primary`, `selectedForegroundColor: AppColors.onPrimary`.
- Optional fallback "custom value" `TextField` row below the chip strip.

**When to use**: 3–8 fixed preset values where the user usually picks one of the presets but may type a custom value.

**When NOT to use**: more than 8 presets (use Wrap — L3.3); presets that would line-wrap (also Wrap); presets where the user almost always types a custom value (use a regular field).

### 3.3 Wrap Multi-Select (Categories)

**Use case**: pick one value from an unbounded category set that may have user-added entries; chips must remain visible without horizontal clipping.
**Reference implementation**: [`RecipeCategoryChips`](../lib/widgets/recipe_form/recipe_category_chips.dart) using [`PillChip`](../lib/widgets/shared/pill_chip.dart).

**Anatomy**:
- `Wrap` with `spacing: AppSpacing.sm`, `runSpacing: AppSpacing.sm`.
- Trailing `+ 其他` chip opens an `AlertDialog` for custom entry.
- If a previously-entered custom value is the current selection, it gets injected as a chip alongside the presets.

**When to use**: categories or tags where the set may grow over time and ordering doesn't matter.

**When NOT to use**: small fixed sets (use horizontal — L3.2); single-value fields (use a `TextField`).

### 3.4 Bottom-Sheet Single-Select

**Use case**: pick one value from a medium/large fixed set; surface is too wide for chips, but a `DropdownButton` would feel cramped on mobile.
**Reference implementation**: [`UnitDropdown`](../lib/widgets/recipe_form/unit_dropdown.dart).

**Anatomy**:
- Trigger: a `PillChip` showing the current value, with a trailing chevron icon.
- On tap: show a Material `showModalBottomSheet`, listing options as taps; selected option highlighted.

**When to use**: 5+ fixed options (units, currencies); options have category groupings.

**When NOT to use**: 2-3 binary toggles (use chip row — L3.2); free-form input (use `TextField`).

### 3.5 Reorderable List

**Use case**: a list of user-managed items (ingredients, steps) where order matters and users need to rearrange.
**Reference implementation**: ingredients/steps sections in [`custom_recipe_form_screen.dart`](../lib/screens/custom_recipe_form_screen.dart).

**Anatomy**:
- `ReorderableListView` with `buildDefaultDragHandles: false`; each row gets an explicit `ReorderableDragStartListener` wrapping a drag handle icon.
- Each item is a row with: drag handle (left), content (center, expanding), delete IconButton (right).
- A trailing "+ Add" row outside the reorderable list itself.

**When to use**: ordered lists 3+ items; cooking steps; anything where the user needs to reorder.

**When NOT to use**: single-item edits (just a `TextField`); fixed-order lists.

### 3.6 Inline Validation

**Use case**: report validation errors on form inputs without modal interruption.
**Reference implementation**: `errorText` on text fields throughout the recipe form; `RecipeFormCard.hasError` parameter.

**Anatomy**:
- **Field-level**: `TextField`'s native `decoration.errorText` (red 12px below the field).
- **Section-level**: `RecipeFormCard.hasError = true` switches the card border from `1px outlineVariant` → `1.5px error`.
- **No SnackBar for validation**: never use `ScaffoldMessenger.of(context).showSnackBar(...)` to report form validation. SnackBars are reserved for ephemeral non-validation feedback (see L5.1 placeholder).

**When to use**: any user-correctable input error.

**When NOT to use**: irrecoverable backend errors (use a dialog — L5.5 placeholder); confirmations (use a dialog).

### 3.7 Collapsible Banner

**Use case**: a contextual but non-blocking action (e.g. "Try AI import"), should be dismissable without losing access.
**Reference implementation**: [`AiCollapsibleBanner`](../lib/widgets/recipe_form/ai_collapsible_banner.dart).

**Anatomy**:
- Default state: collapsed, 1-row tappable summary with leading icon.
- Expanded: shows the actual call-to-action body (button or input row).
- State toggled by tapping the summary row.

**When to use**: AI-assist entry points; dismissable suggestions.

**When NOT to use**: blocking primary actions (use a regular Card or button); permanent help text (use a small subtitle).

### 3.8 Difficulty Rating

**Use case**: pick a discrete level on a fixed scale (e.g. 1-5).
**Reference implementation**: [`DifficultyStars`](../lib/widgets/recipe_form/difficulty_stars.dart).

**Anatomy**:
- A row of N tappable star icons; selected stars filled with `AppColors.primary`, unselected outlined with `AppColors.outline`.
- Tapping a star sets the value to that index.

**When to use**: any 1–5 discrete rating.

**When NOT to use**: continuous values (use a Slider); >5 levels (use a `PillChip` row).

### 3.9 Number Stepper *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 4 (`add_ingredient` redesign).
**Inputs to consider when filling in**: `add_ingredient_screen` ingredient quantity entry; the `+/–` button pattern in shopping list quick-add (`quick_add_field.dart`); whether to allow direct typing alongside the steppers.

### 3.10 Icon Chip

**Use case**: a chip label that benefits from a leading icon (status, semantic flag).
**Reference implementation**: [`PillChip`](../lib/widgets/shared/pill_chip.dart) constructed with the `icon` parameter.

**Anatomy**:
- Default `iconSize: 16`, `iconLabelGap: 6` (intentionally tighter than text-only for visual balance).
- `iconForegroundColor` defaults to follow the label color; can be overridden for emphasis (e.g. error icon).

**When to use**: AI draft markers; freshness state; category tags with iconography.

**When NOT to use**: action buttons (use FilledButton.icon or IconButton); decorative only (use a Row with Icon + Text).

````

- [ ] **Step 7.2: Verify section line count**

```bash
awk '/^## L3 Component Patterns/,/^## L4 Page Patterns/' docs/design-system.md | wc -l
```

Expected: roughly 180-220 lines.

- [ ] **Step 7.3: Commit**

```bash
git add docs/design-system.md
git commit -m "docs(design-system): fill L3 Component Patterns (10 entries, 1 placeholder)"
```

---

## Task 8: Fill L4 Page Patterns section (7 entries: 3 complete + 4 placeholder)

**Files:**
- Modify: `docs/design-system.md`

- [ ] **Step 8.1: Replace L4 placeholder with full content**

In `docs/design-system.md`, replace the line `> Filled in Task 8.` (under `## L4 Page Patterns`) with:

````markdown
### 4.1 Scaffold + SafeArea

**Use case**: every screen needs a consistent root.
**Reference implementation**: [`AppShell.build`](../lib/app.dart) for top-level shell; pushed screens use plain `Scaffold`.

**Convention**:
- Top-level shell (`FreshPantryApp` → `AppShell`): wraps the body in `SafeArea`, hosts the `IndexedStack` of main 4 screens, sets `extendBody: true` so the `BottomNavBar` floats over content.
- Pushed screens (recipe form, ingredient detail, etc.): use plain `Scaffold` without `SafeArea` (the route's `MaterialPageRoute` provides one transitively from the system Material app); explicit `SafeArea` wrap is **not** required and should not be added.

**Background**: always `AppColors.surface` via `scaffoldBackgroundColor` in the theme — do not override per-screen.

### 4.2 AppBar

**Use case**: top chrome on each screen.

**Convention**:
- **Main 4 screens** (Dashboard / Inventory / Add / Shopping): use the custom [`TopAppBar`](../lib/widgets/common/top_app_bar.dart) widget, which provides app title, search trigger, and AI settings entry. Do not use Material `AppBar` here.
- **Pushed screens** (form, detail, draft review, settings): use Material `AppBar`. The theme makes it transparent + `scrolledUnderElevation: 0` (matching the scaffold background).
- `kAppSystemOverlayStyle` (defined in `app_theme.dart`) is used at both `AnnotatedRegion` (root) and `AppBarTheme.systemOverlayStyle` — do not change per-screen.

### 4.3 Bottom Navigation + IndexedStack

**Use case**: navigate between the 4 main screens without losing scroll/state.
**Reference implementation**: [`BottomNavBar`](../lib/widgets/common/bottom_nav_bar.dart) inside [`AppShell`](../lib/app.dart).

**Convention**:
- 4 destinations driven by `navigationProvider` (Riverpod state).
- `IndexedStack` keeps each screen's `State` alive across tab switches (so user scroll position survives).
- The center "+" affordance is a custom button inside `BottomNavBar`, not a Material FAB.
- Pushed screens (via `Navigator.of(context).push`) appear over the entire `Scaffold` and hide the bottom nav by virtue of being a new route.

### 4.4 Horizontal Padding *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 2 (dashboard redesign).
**Inputs to consider**: current screens use a mix of 16/20/24; recipe form uses 24 (`AppSpacing.xxl`); main 4 screens are inconsistent. Decide whether all main screens use 24, or whether dense list screens (inventory) get 16.

### 4.5 Vertical Section Spacing *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 2 (dashboard redesign).
**Inputs to consider**: gap between sections (cards) on a screen; recipe form uses ~16 between cards. Decide on a single gap value (`lg=16` or `xl=20`).

### 4.6 Section Header *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 2 (dashboard redesign).
**Inputs to consider**: existing screen uses a mix of bare titles, titles with trailing actions ("View All"), and titles with leading icons. Decide on canonical anatomy: title style (`titleLarge`?), optional trailing button, optional leading icon, what goes inside vs outside the section card.

### 4.7 FAB / Center "+" Button *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 5 (shopping list redesign) or phase 3 (inventory redesign), whichever lands first.
**Inputs to consider**: current center "+" lives inside `BottomNavBar`; some screens (inventory) have no FAB; some screens have action buttons inline; Material's standard FAB is not used. Decide whether to add a per-screen FAB pattern or keep the bottom nav center button as the only "create" affordance.

````

- [ ] **Step 8.2: Verify section line count**

```bash
awk '/^## L4 Page Patterns/,/^## L5 Interaction Patterns/' docs/design-system.md | wc -l
```

Expected: roughly 70-90 lines.

- [ ] **Step 8.3: Commit**

```bash
git add docs/design-system.md
git commit -m "docs(design-system): fill L4 Page Patterns (3 complete, 4 placeholders)"
```

---

## Task 9: Fill L5 Interaction Patterns + Appendices

**Files:**
- Modify: `docs/design-system.md`

- [ ] **Step 9.1: Replace L5 placeholder with full content**

In `docs/design-system.md`, replace the line `> Filled in Task 9.` (under `## L5 Interaction Patterns`) with:

````markdown
### 5.1 SnackBar *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: first phase that needs an ephemeral non-validation message (likely phase 3 inventory or phase 4 add).
**Inputs to consider**: SnackBar must NOT be used for form validation (see L3.6); decide on: confirmation messages ("Saved"), undoable destructive actions ("Deleted — Undo"), background sync errors. Consult [`app_snackbar_test.dart`](../test/app_snackbar_test.dart) for any existing wrappers.

### 5.2 Inline Validation

See L3.6 — inline validation pattern is fully specified there. SnackBars must not be used for validation.

### 5.3 Loading *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 4 (`add_ingredient` redesign), where AI parsing introduces the first non-trivial async operation.
**Inputs to consider**: spinner placement (inline next to button, full-screen overlay, top-of-page bar?); recipe form's "save section" already has an inline spinner pattern — assess if it generalizes.

### 5.4 Empty State *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: first screen with empty-able content (likely phase 5 shopping list or phase 3 inventory).
**Inputs to consider**: anatomy (icon + headline + body + CTA?); whether empty state is a separate widget or inline within the list.

### 5.5 Confirmation Dialog *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: first phase that needs destructive confirmations.
**Inputs to consider**: existing `AlertDialog` usage in [`RecipeCategoryChips._promptCustomCategory`](../lib/widgets/recipe_form/recipe_category_chips.dart) for input prompts; whether to keep Material `AlertDialog` or build a project-themed dialog widget; standard button order (Cancel | Confirm vs Confirm | Cancel); destructive button styling (use `error` family — see L2.4).

### 5.6 Bottom Sheet *(Placeholder)*

**Status**: Placeholder (partially covered in L3.4 for selection).
**To be filled in**: first phase that needs a non-selection bottom sheet (e.g. multi-step input flow).
**Inputs to consider**: anatomy (drag handle, title, content, primary action button); modal vs persistent; ergonomic max height.

````

- [ ] **Step 9.2: Replace Appendix A placeholder**

In `docs/design-system.md`, replace the line `> Filled in Task 9.` (under `## Appendix A: Transient Inconsistencies`) with:

````markdown
The following inconsistencies between this document and the codebase exist as of phase 0 close. Each is scheduled for cleanup in phase 1 (shared widget library extraction). New code should follow this document, not the cited code.

| ID | Inconsistency | File | Phase 1 fix |
|---|---|---|---|
| T1 | `PillChip` default `fontSize: 13` violates the L1.4 rule (sizes must come from the typography token ladder; closest is `labelLarge` = 14). | [`lib/widgets/shared/pill_chip.dart`](../lib/widgets/shared/pill_chip.dart) | Change default to use `labelLarge` size (14) or remove the parameter and source style from `Theme.of(context).textTheme.labelLarge`. |
| T2 | `RecipeFormCard` self-implements its container with `Container` + `BoxDecoration` instead of using Material `Card` (so it bypasses `cardTheme` from L2.1). | [`lib/widgets/recipe_form/recipe_form_card.dart`](../lib/widgets/recipe_form/recipe_form_card.dart) | Refactor into a shared `SectionCard` widget that uses `Card` and inherits the theme. |
| T3 | `RecipeFormCard` hardcodes its title weight as `FontWeight.w800` instead of using `AppTypography.sectionTitle`. | same file as T2 | Use `AppTypography.sectionTitle` directly. |

**Additionally found during phase 0 audit**: two more chip implementations exist alongside `PillChip` and should be unified in phase 1:

- `_CategoryChip` in [`lib/widgets/common/category_chips.dart`](../lib/widgets/common/category_chips.dart) (used for top-of-screen category switcher).
- `AiDraftFieldChip` in [`lib/widgets/shared/ai_draft_field.dart`](../lib/widgets/shared/ai_draft_field.dart) (AI draft state badge).

Phase 1 should consolidate all three into `PillChip` (extending its parameter set if needed).

````

- [ ] **Step 9.3: Replace Appendix B placeholder**

In `docs/design-system.md`, replace the line `> Filled in Task 9.` (under `## Appendix B: Decision Log`) with:

````markdown
The following 7 decisions were made during phase 0 brainstorming (2026-05-09 to 2026-05-10) to reconcile two pre-existing inconsistent design systems: the Material theme in `app_theme.dart` and the de facto patterns in the recipe form widgets. Each decision favored the recipe form patterns (the project's most recent, post-redesign source of truth) over the older theme defaults.

| # | Decision | Chose | Over | Rationale |
|---|---|---|---|---|
| 1 | Card radius | 16 (`AppRadius.lg`) | 24 (theme default) | Recipe form's denser layout reads better at 16; preserves consistency with form section grouping. |
| 2 | Card background | `surfaceContainerLowest` (white) | `surfaceContainer` (theme default) | Recipe form pattern; provides micro-contrast against `surfaceBright` scaffold (`#FCF9F6` vs `#FFFFFF`). |
| 3 | Card border | 1px `outlineVariant` (1.5px `error` when invalid) | none (theme default) | A flat white card on a near-white scaffold "disappears" without an outline; recipe form found this through usage. |
| 4 | Chip implementation | `PillChip` (project's only chip) | Material `Chip` family | Recipe form has zero Material `Chip` usage; eliminating one codebase variant simplifies the model. The chipTheme persists only as fallback for any future Material `Chip(...)` regression. |
| 5 | Chip default background | `surfaceContainerLow` | `surfaceContainerHigh` (theme default) | Matches `PillChip` default; fits the layered surface scale on cards. Documented contrast caveat (L2.2) for white-on-white case. |
| 6 | Chip font size | 14 (`labelLarge`) | 13 (PillChip current default) | 13 is not on the typography ladder; 14 fits `labelLarge`. PillChip's `13` is recorded as transient inconsistency T1 for phase 1 fix. |
| 7 | Section title weight | `AppTypography.sectionTitle` (titleMedium + w800) | `titleMedium` w600 (theme default) or hardcoded `w800` (recipe form) | Naming the override surfaces the pattern; future widgets get a single import to follow. |

````

- [ ] **Step 9.4: Verify L5 + Appendix line count**

```bash
awk '/^## L5 Interaction Patterns/,/^## Appendix B/' docs/design-system.md | wc -l
awk '/^## Appendix A/,/^## Appendix B/' docs/design-system.md | wc -l
awk '/^## Appendix B/,EOF' docs/design-system.md | wc -l
```

Expected: L5 ~50-70 lines; Appendix A ~30-40 lines; Appendix B ~25-35 lines.

- [ ] **Step 9.5: Commit**

```bash
git add docs/design-system.md
git commit -m "docs(design-system): fill L5 interaction patterns + appendices (transient/decisions)"
```

---

## Task 10: Final verification — analyze + test + visual smoke + R1-R4 self-review

**Files:** none (verification only)

- [ ] **Step 10.1: Static analysis must be clean**

```bash
flutter analyze
```

Expected: same baseline as before phase 0 (no new info/warning/error introduced). If new lint complaints appear, they relate to changes in tasks 1–3; fix them before continuing.

- [ ] **Step 10.2: Full test suite must be green**

```bash
flutter test
```

Expected: all tests pass. Pay attention to:
- `test/app_theme_tokens_test.dart` — the new groups added in tasks 1-3.
- `test/widget_test.dart` — the smoke test that pumps the full app; if it fails, a theme change caused a runtime regression.
- Any `*_test.dart` that touches `Card(...)` / `Chip(...)` directly — none should exist (audit confirmed zero call sites), but if a hidden one shows up, investigate.

- [ ] **Step 10.3: Manual visual smoke test — main 4 screens**

Run the app on a simulator/device:

```bash
flutter run
```

Walk through each main screen and confirm no unexpected visual changes:
- **Dashboard**: stat cards, alert cards, storage summary, recent additions, curators tip — visually identical to phase-0-pre.
- **Inventory**: ingredient cards, category chips at top, search overlay — visually identical.
- **Add**: ingredient quick entry, draft review screen — visually identical.
- **Shopping**: shopping items, smart planner card, quick add — visually identical.

Phase 0 should produce **zero** visual changes here, because the cardTheme/chipTheme adjustments only affect Material `Card`/`Chip` users, which is currently zero call sites.

- [ ] **Step 10.4: Manual visual smoke test — recipe form**

Within the running app:
1. Tap the share intent flow OR navigate via `+` to start a new recipe → enter `CustomRecipeFormScreen`.
2. Confirm: section cards visually identical (white, 16 radius, 1px outline border), chips visually identical (pill, surfaceContainerLow background), section titles still bold (w800), drag handles work, validation flows still work.
3. Edit an existing recipe via `MyRecipesScreen` if reachable — confirm same.

**Expected**: zero visual change. If any difference is observed, it indicates an incorrect assumption in §5 of the spec (PillChip / RecipeFormCard not bypassing the theme as expected) and should be investigated before declaring phase 0 done.

- [ ] **Step 10.5: Document R1-R4 self-review (mental checklist)**

Open `docs/design-system.md` and verify (no automation; visual scan):
- **R1**: Appendix A "Transient Inconsistencies" lists T1/T2/T3 + the two extra chip implementations (`_CategoryChip`, `AiDraftFieldChip`).
- **R2**: All 11 placeholders list the phase responsible (3.9 → phase 4; 4.4-4.6 → phase 2; 4.7 → phase 3 or 5; 5.1/5.3/5.4/5.5/5.6 → various phases).
- **R3**: First section after the title has the "About `design/html/`" deprecation note.
- **R4**: Every reference implementation path is real — sample-check 5 paths via `ls` or `grep`:

```bash
ls lib/widgets/recipe_form/recipe_form_card.dart
ls lib/widgets/recipe_form/cooking_time_row.dart
ls lib/widgets/shared/pill_chip.dart
ls lib/widgets/recipe_form/unit_dropdown.dart
ls lib/app.dart
```

All 5 must exist.

- [ ] **Step 10.6: No commit on this task**

This task is verification only. If any check failed, return to the failing task; if all passed, phase 0 is **done**.

Phase 0 close-out: announce completion to the user, summarize the 9 commits made (tasks 1-9), confirm the spec's Definition of Done D1-D4 and Q1-Q4 and R1-R4 all satisfied, and surface the 5-item phase-1 follow-up list (T1, T2, T3, plus consolidating `_CategoryChip` and `AiDraftFieldChip` into `PillChip`).

---

## Self-Review

**Spec coverage check:**

| Spec section | Implemented in |
|---|---|
| §2.1 (Scope: include) D1 docs/design-system.md | Tasks 4-9 |
| §2.1 D2 spec doc | Already done (committed as `9661485`) |
| §2.1 D3 app_theme.dart card+chip | Tasks 2, 3 |
| §2.1 D4 sectionTitle getter | Task 1 |
| §2.2 (Scope: exclude) N1-N8 | Implicit — plan only touches files listed in §File Structure |
| §6 (調和決定) #1-7 | Tasks 1, 2, 3 (code) + Task 9 Appendix B (doc) |
| §7 (L1-L5 條目清單) | Tasks 5, 6, 7, 8, 9 |
| §8 (代碼改動) §8.1 cardTheme | Task 2 step 2.3 (exact match) |
| §8 (代碼改動) §8.1 chipTheme | Task 3 step 3.3 (exact match) |
| §8 (代碼改動) §8.2 sectionTitle | Task 1 step 1.3 (exact match) |
| §9 (Transient 清單) T1-T3 | Task 9 step 9.2 (Appendix A) |
| §10 (DoD) D1 | Tasks 4-9 |
| §10 (DoD) D2 | already done |
| §10 (DoD) D3 | Tasks 2, 3 |
| §10 (DoD) D4 | Task 1 |
| §10 (DoD) Q1 flutter analyze | Task 10 step 10.1 |
| §10 (DoD) Q2 flutter test | Task 10 step 10.2 |
| §10 (DoD) Q3 main 4 visual smoke | Task 10 step 10.3 |
| §10 (DoD) Q4 recipe form unchanged | Task 10 step 10.4 |
| §10 (DoD) R1 transient section | Task 9 step 9.2 + Task 10 step 10.5 |
| §10 (DoD) R2 placeholder list | Tasks 7-9 + Task 10 step 10.5 |
| §10 (DoD) R3 deprecation note | Task 4 step 4.1 (in skeleton) + Task 10 step 10.5 |
| §10 (DoD) R4 widget refs valid | Task 10 step 10.5 |

No gaps.

**Placeholder scan**: tasks contain only the kind of "placeholders" that are intentional (the 11 doc placeholders for later phases). Plan steps themselves contain no TBD, TODO, "implement later", or "follow this format" without showing the format.

**Type / API consistency**:
- `AppTypography.sectionTitle` referenced in Task 1 (definition), Task 9 (Appendix B), Task 7 (3.1 Section Card anatomy) — same name throughout.
- `cardTheme` / `chipTheme` shape, color, side properties consistent across Tasks 2, 3 tests and the L2.1, L2.2 doc entries.
- `AppColors.outlineVariant`, `AppColors.surfaceContainerLowest`, `AppColors.surfaceContainerLow`, `AppColors.primary` all match the names in [`app_colors.dart`](../lib/theme/app_colors.dart) (verified during audit).
- `AppRadius.lg = 16` and `AppRadius.pill = 999` consistent with [`app_radius.dart`](../lib/theme/app_radius.dart).

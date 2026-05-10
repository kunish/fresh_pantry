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

### 1.1 Color

**Definition**: Project color palette, derived from a green-forward food/freshness brand.
**Source**: [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart) (`AppColors`).

The palette has four functional families plus an 8-token surface scale:

- **Primary** — `primary` (`#0F5238`), `primaryContainer`, `primaryFixed`. Brand green; used for FAB, active states, primary buttons.
- **Secondary** — `secondary` (`#9B4500`), `secondaryContainer` (`#FC8A40`), `secondaryFixed`. Burnt-orange accent; used for warnings, urgency badges.
- **Tertiary** — `tertiary` / `tertiaryContainer` / `tertiaryFixedDim`. Muted gold; used sparingly for tier-3 accents (curator's tip, etc.).
- **Error** — `error` / `errorContainer` family. Validation, destructive actions.
- **Surface scale** — 5-step container scale (`surfaceContainerLowest` `#FFFFFF` → `surfaceContainerLow` → `surfaceContainer` → `surfaceContainerHigh` → `surfaceContainerHighest` `#E5E2DF`) plus `surface` / `surfaceBright` (`#FCF9F6`) and `surfaceDim`.

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

**Definition**: 15-style type scale + one named-pattern token (`sectionTitle`).
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

---

## L2 Themes

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

---

## L3 Component Patterns

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
**Inputs to consider**: `add_ingredient_screen` ingredient quantity entry; the `+/–` button pattern in shopping list quick-add (`quick_add_field.dart`); whether to allow direct typing alongside the steppers.

### 3.10 Icon Chip

**Use case**: a chip label that benefits from a leading icon (status, semantic flag).
**Reference implementation**: [`PillChip`](../lib/widgets/shared/pill_chip.dart) constructed with the `icon` parameter.

**Anatomy**:
- Default `iconSize: 16`, `iconLabelGap: 6` (intentionally tighter than text-only for visual balance).
- `iconForegroundColor` defaults to follow the label color; can be overridden for emphasis (e.g. error icon).

**When to use**: AI draft markers; freshness state; category tags with iconography.

**When NOT to use**: action buttons (use FilledButton.icon or IconButton); decorative only (use a Row with Icon + Text).

---

## L4 Page Patterns

### 4.1 Scaffold + SafeArea

**Use case**: every screen needs a consistent root.
**Reference implementation**: [`AppShell.build`](../lib/app.dart) for top-level shell; pushed screens use plain `Scaffold`.

**Convention**:
- Top-level shell (`FreshPantryApp` → `AppShell`): wraps the body in `SafeArea`, hosts the `IndexedStack` of main 4 screens, sets `extendBody: true` so the `BottomNavBar` floats over content.
- Pushed screens (recipe form, ingredient detail, etc.): use plain `Scaffold` without a screen-level `SafeArea`. The `AppBar` reserves the top status-bar padding via `MediaQuery`, and bottom action bars wrap their own `SafeArea` where needed (e.g. the save section in [`custom_recipe_form_screen.dart`](../lib/screens/custom_recipe_form_screen.dart)). A redundant outer `SafeArea` wrap is not needed and would cause double-padding.

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
**Inputs to consider**: current screens use a mix — dashboard and inventory use 24 (`AppSpacing.xxl`); recipe form uses 16 (`AppSpacing.lg`); other padding values (e.g. 20 / `AppSpacing.xl`) appear sporadically. Decide whether all main screens use 24, or whether dense list / form screens get 16.

### 4.5 Vertical Section Spacing *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 2 (dashboard redesign).
**Inputs to consider**: gap between sections (cards) on a screen; recipe form uses 12 (`AppSpacing.md`) between section cards via the top of each card's `EdgeInsets.fromLTRB`. Decide on a single canonical gap value (`md=12`, `lg=16`, or `xl=20`).

### 4.6 Section Header *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 2 (dashboard redesign).
**Inputs to consider**: existing screen uses a mix of bare titles, titles with trailing actions ("View All"), and titles with leading icons. Decide on canonical anatomy: title style (`titleLarge`?), optional trailing button, optional leading icon, what goes inside vs outside the section card.

### 4.7 FAB / Center "+" Button *(Placeholder)*

**Status**: Placeholder.
**To be filled in**: phase 5 (shopping list redesign) or phase 3 (inventory redesign), whichever lands first.
**Inputs to consider**: current center "+" lives inside `BottomNavBar`; some screens (inventory) have no FAB; some screens have action buttons inline; Material's standard FAB is not used. Decide whether to add a per-screen FAB pattern or keep the bottom nav center button as the only "create" affordance.

---

## L5 Interaction Patterns

> Filled in Task 9.

---

## Appendix A: Transient Inconsistencies

> Filled in Task 9.

## Appendix B: Decision Log

> Filled in Task 9.

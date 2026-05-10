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

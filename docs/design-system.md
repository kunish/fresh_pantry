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

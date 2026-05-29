# ADR-0002: AI draft parsers keep separate validation strategies

Date: 2026-05-29

## Status

Accepted

## Context

An architecture review flagged `AiIngredientParser` and `AiRecipeParser` as
duplicating "extract → validate → wrap a draft" and suggested folding them into
one shared `AiDraftParser` seam with a single malformed-entry policy.

On inspection the shareable work is already shared:

- JSON extraction lives once in `utils/ai_json_extract.dart`
  (`extractJsonArrayWithFallbacks` / `extractJsonObjectWithFallbacks`).
- `AiChatFn`, `AiParseException`, and `DraftField.ai(...)` are common already.

What differs is **intentional and correct**, not an inconsistency to unify:

- **Ingredient parsing** decodes a JSON *array* into a list of drafts and is
  **per-row resilient** — a malformed row is skipped so one bad entry never
  loses the rest of a paste.
- **Recipe parsing** decodes a JSON *object* into a single draft and is
  **all-or-nothing** — a missing required field throws, because there is no
  "partial recipe" worth keeping.

The remaining per-parser code is field validation specific to each entity
(`difficulty` clamped 1–5, `cookingMinutes` defaulted, `shelfLifeDays` must be
positive). These are not duplicates; they validate different fields.

## Decision

Do **not** introduce a shared `AiDraftParser` seam. Keep the two parsers
separate. A single shared malformed-entry policy would be wrong for one of the
two shapes (list resilience vs object all-or-nothing).

Revisit only if a **third** AI-to-draft flow appears that shares one of the two
shapes — at that point the resilience strategy, not the parser, is what would
be shared.

## Consequences

- The two parsers stay small and read in their own domain terms.
- No speculative abstraction is added for two callers (YAGNI).
- Future architecture reviews should not re-suggest merging them without a third
  flow that shares a shape.

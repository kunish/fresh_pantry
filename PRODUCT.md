# Product

## Register

product

## Users

The maintainer and their household — a small, known group (family sharing over
Supabase), not an anonymous user base. This is a **self-use app (A-mode)**: the
person who builds it is the person who uses it. They reach for it in the kitchen,
mid-task — putting groceries away, deciding what to cook, checking what's about to
expire. Context is hands-busy, glance-and-go, often one-handed on a phone.

The job to be done: *"keep an honest picture of what's in the house, and surface
what needs attention before it spoils — with as little bookkeeping as possible."*

## Product Purpose

Fresh Pantry tracks fridge/freezer/pantry stock, signals expiry and low stock,
and suggests recipes from what's actually on hand. Stock changes flow through
**Proposals** (from AI paste-import, recipe completion, or shopping) that the user
reviews and confirms before they apply atomically to Inventory.

It exists to remove the friction of manual pantry tracking for one household.
Success is **not** engagement or retention — it's that the maintainer trusts the
inventory enough to rely on it, and that keeping it accurate costs almost nothing.
A good day is one where the app quietly prevented food waste and the user barely
noticed doing any data entry.

## Brand Personality

Warm and domestic — the feel of a well-kept kitchen, not a database. Friendly,
calm, unhurried. Three words: **homey, quiet, trustworthy.**

The UI should feel like a helpful shelf label, not a dashboard. Warmth comes from
typography, color, and tone — never from decoration for its own sake. Voice is
plain and kind ("about to expire", "still good"), never alarmist or gamified.

## Anti-references

- **Not a gamified consumer app.** No streaks, badges, points, engagement loops,
  or push nagging. There is no retention metric to chase — this is self-use.
- **Not an enterprise dashboard.** No cold data-grid density, no KPI tiles, no
  corporate-tool sterility. Inventory is a pantry, not a spreadsheet.
- Not trend-chasing visual novelty (glassmorphism, gradients, flourish motion)
  layered on for its own sake.

## Design Principles

1. **Maintainer-first, not retention-first.** Every screen optimizes the cost of
   keeping the pantry accurate, never time-in-app. If a feature adds stickiness
   but adds friction, it loses.
2. **Review before mutate.** Stock never changes silently — Proposals are shown,
   editable, and overridable before they apply. The UI's job is to make the
   proposed change legible at a glance and trivial to accept or correct.
3. **Trust the default, allow the override.** `IngredientIdentity` already decides
   merge-vs-new-batch; the UI surfaces that default plainly and lets the user
   override it — it never makes the user re-derive the system's reasoning.
4. **Surface urgency quietly.** Urgency Status (fresh / soon / urgent / expired /
   low-stock) drives calm, legible signals — color and badge — not interruption.
   The pantry tells you what needs attention without shouting.
5. **Local-first calm.** Works offline; sync is background and invisible when it's
   working. The user should never have to think about sync state to do their task.

## Accessibility & Inclusion

Standard iOS accessibility. Support Dynamic Type (layouts must not break at large
text sizes), VoiceOver, and `prefers-reduced-motion` (provide a non-motion
alternative for any transition). Urgency must never be conveyed by color alone —
pair it with a label, icon, or text so it survives color blindness and grayscale.
Meet WCAG AA contrast for body text and interactive elements.

# ADR-0003: Sync metadata stays on the domain model

Date: 2026-05-29

## Status

Accepted

> **⚠️ Status: Superseded (Flutter-era)**
> 本 ADR 描述的是 Flutter/Dart 版本中同步元数据挂载在领域模型上的方案（`lib/widgets/`、`lib/sync/remote_row_codec.dart`、Flutter `copyWith`/`hashCode` 等）。
> Flutter 版本已由 SwiftUI 重写取代，当前同步实现使用 SwiftData `@ModelActor` repositories，见 `apps/ios/FreshPantry/Persistence/`。
> 本 ADR 保留仅供历史参考，不代表现行架构。

## Context

An architecture review proposed moving the sync-only fields
(`remoteVersion`, `clientUpdatedAt`, `deletedAt`) off `Ingredient`,
`ShoppingItem`, and `Recipe` into a `SyncEnvelope<T>` wrapper, on the premise
that versioning state "leaks into widgets and notifiers."

The premise does not hold against the code:

- A grep of `lib/widgets/` and `lib/screens/` finds **zero** reads of these
  fields — there is no UI leak.
- The only non-model, non-`lib/sync/` references are in the three notifiers, all
  legitimate sync calls (`baseVersion: x.remoteVersion`).
- A `SyncMetadata` value type and `Ingredient.syncMetadata` getter already
  exist, so the wrapper is available if a real need ever appears.

Extracting the fields would touch every model's `==`, `hashCode`, `toJson`,
`fromJson`, `copyWith`, and every construction site — a large, high-regression
change for a leak that does not exist.

The genuinely valuable half of that review item — consolidating the six Supabase
row-mapping functions — was done separately (see `lib/sync/remote_row_codec.dart`
and `test/remote_row_codec_test.dart`).

## Decision

Keep `remoteVersion` / `clientUpdatedAt` / `deletedAt` as fields on the domain
models. Do not introduce a `SyncEnvelope` wrapper.

## Consequences

- Models stay serialization-symmetric with their Supabase rows via the row codec.
- No churn across model equality/serialization/copyWith and their call sites.
- If a future feature genuinely needs to read sync state from UI, reconsider —
  `SyncMetadata` is the seam to grow, and this ADR should be revisited then.

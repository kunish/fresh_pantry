-- User-defined inventory tags (「囤货」「待用完」「孩子的」…) — a cross-cutting
-- grouping dimension beyond category/storage, filtered client-side.
--
-- The native client maps `Ingredient.tags` to this column via the columnar
-- inventory_items codec (RemoteRowCodec.inventoryRowMap), so the upsert always
-- writes a `tags` value. Stored as jsonb (a string array) to mirror the domain
-- shape directly; not-null with a `[]` default so legacy rows and any client
-- that omits the key still read back as "no tags".
alter table public.inventory_items
  add column if not exists tags jsonb not null default '[]'::jsonb;

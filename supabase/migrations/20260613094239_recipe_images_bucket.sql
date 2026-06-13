-- recipe-images Storage bucket: the global HowToCook catalog covers (364), moved
-- off the app bundle (~111MB) onto Supabase Storage so the app ships slim and
-- covers stream + disk-cache on device. Public read like `avatars` (served via
-- getPublicURL / CDN); no anon/authenticated INSERT policy — the catalog is
-- curated by the recipe pipeline, so writes are service-role / migration only.
--
-- Applied to production via MCP at version 20260613094239. The one-time upload of
-- the 364 covers used a TRANSIENT anon-write policy (opened + dropped outside this
-- migration, see apps/recipe-pipeline/README.md); the durable state is read-only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('recipe-images', 'recipe-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "recipe_images_read_public" on storage.objects;
create policy "recipe_images_read_public" on storage.objects
  for select to public
  using (bucket_id = 'recipe-images');

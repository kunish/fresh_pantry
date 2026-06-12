-- Avatars upload fix — root cause: a MISSING SELECT policy on storage.objects.
--
-- The app uploads with `upsert: true`, so storage-api issues
-- `INSERT ... ON CONFLICT (...)`. PostgreSQL's ON CONFLICT path must first READ the
-- table to detect a conflict, which requires a SELECT RLS policy. storage.objects
-- had INSERT/UPDATE/DELETE policies but NO SELECT policy (the bucket's "public"
-- flag only serves reads over the CDN path — it is NOT an RLS SELECT policy). With
-- no SELECT policy, every upsert was rejected with
-- `42501 new row violates row-level security policy for table "objects"`, since the
-- feature shipped (2026-06-11). A plain INSERT (no ON CONFLICT) was never the path
-- the app took, which is why it looked like the INSERT policy was failing.
--
-- Verified at the database level: as role `authenticated` with the user's JWT
-- claims, a plain insert succeeded but `INSERT ... ON CONFLICT` failed — and adding
-- the SELECT policy made the upsert succeed while still rejecting cross-user writes.
-- Storage DOES propagate the caller identity (auth.uid() resolves correctly inside
-- the storage session); the owner-scoped checks are sound, so we keep per-user
-- isolation and simply add the SELECT policy the upsert needs.
--
-- Drop-then-create keeps the migration idempotent (repo convention, cf.
-- 20260611120000_profile_personal_info.sql). NOTE: filename retained for migration
-- history continuity; the final design is owner-scoped writes + public read, not an
-- open bucket.

-- Owner-scoped writes: a user may only write objects under their own {auth.uid()}/
-- prefix. (Recreated to be self-contained / idempotent.)
drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- THE FIX: a SELECT policy is required for `INSERT ... ON CONFLICT` (upsert) to
-- read potential conflicts. The avatars bucket is public-read, so a public SELECT
-- policy scoped to the bucket is the correct grant.
drop policy if exists "avatars_read_public" on storage.objects;
create policy "avatars_read_public" on storage.objects
  for select to public
  using (bucket_id = 'avatars');

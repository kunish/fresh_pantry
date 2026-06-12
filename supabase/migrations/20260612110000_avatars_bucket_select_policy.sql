-- Avatars upload fix — root cause: a MISSING SELECT policy on storage.objects.
--
-- The app uploads with `upsert: true`, so storage-api issues
-- `INSERT ... ON CONFLICT (...)`. PostgreSQL's ON CONFLICT path must first READ the
-- table to detect a conflict, which requires a SELECT RLS policy. storage.objects
-- had INSERT/UPDATE/DELETE policies but NO SELECT policy (the bucket's "public"
-- flag only serves reads over the CDN path — it is NOT an RLS SELECT policy). With
-- no SELECT policy, every upsert was rejected with
-- `42501 new row violates row-level security policy for table "objects"`.
--
-- Applied to production via MCP (~2026-06-12 11:00 UTC). Git must keep this version
-- timestamp so Supabase Preview reconciles schema_migrations (cf. 20260601035956).

drop policy if exists "avatars_read_public" on storage.objects;
create policy "avatars_read_public" on storage.objects
  for select to public
  using (bucket_id = 'avatars');

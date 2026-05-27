# Fresh Pantry Supabase

Supabase project files for family sharing.

Commands:

```bash
npm run supabase:start
npm run supabase:reset
npx -y supabase@2.101.0 test db
npm run supabase:status
```

Security rules:

- All shared tables have RLS enabled.
- Household data is visible only to `household_members`.
- Owner-only actions are household configuration, invites, and member removal.

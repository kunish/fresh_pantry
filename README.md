# Fresh Pantry

Fresh Pantry is a local-first household pantry app with a Flutter mobile client, Supabase-backed family sharing, and a thin Cloudflare Worker API surface.

## Layout

- `apps/mobile` - Flutter app.
- `apps/api` - Cloudflare Worker for health checks and invite deep links.
- `supabase` - Supabase migrations, tests, and local configuration.
- `docs/superpowers` - design specs and implementation plans.

## Common Commands

```bash
npm run mobile:analyze
npm run mobile:test
```

Run mobile-specific Flutter commands from `apps/mobile` when debugging locally.

The API and Supabase workspaces are planned for later implementation tasks. Until those directories exist, these root scripts print what will be added and exit successfully; once the directories land, they run the real workspace commands:

```bash
npm run api:test
npm run api:deploy
npm run supabase:status
```

# Fresh Pantry

Fresh Pantry is a local-first household pantry app with a Flutter mobile client, Supabase-backed family sharing, and a thin Cloudflare Worker API surface.

## Layout

- `apps/mobile` - Flutter app.
- `apps/api` - Cloudflare Worker for health checks and invite deep links.
- `supabase` - Supabase migrations, tests, and local configuration.
- `docs/superpowers` - design specs and implementation plans.

## Common Commands

```bash
npm run mobile:pub-get
npm run mobile:analyze
npm run mobile:test
npm run api:test
npm run supabase:status
```

Run mobile-specific Flutter commands from `apps/mobile` when debugging locally.

## Local Development

### Mobile

```bash
npm run mobile:pub-get
npm run mobile:analyze
npm run mobile:test
```

Run the app with Supabase configuration:

```bash
cd apps/mobile
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

`FRESH_PANTRY_API_BASE_URL` defaults to `https://api.fresh-pantry.kunish.eu.org`.

### Supabase

```bash
npm run supabase:start
npm run supabase:reset
npx -y supabase@2.101.0 test db
```

### API

```bash
cd apps/api
npm install
npm test
npx wrangler deploy
```

The production Worker route is `api.fresh-pantry.kunish.eu.org`.

## Supabase Auth Redirect

Email OTP sign-in redirects back into the mobile app with:

```text
com.kunish.freshpantry://signin-callback/
```

Set the Supabase project's Auth Site URL to that deep link and keep the same URL in the redirect allow list before testing magic-link sign-in on devices. For local web testing, run Flutter on port 3000 or add the exact local origin to the redirect allow list.

The checked-in Auth resend interval is tuned for development login testing. Supabase's default SMTP still has a very low hourly email cap; configure a custom SMTP provider before relying on email auth outside personal testing.

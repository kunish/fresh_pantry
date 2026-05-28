# Fresh Pantry Mobile

Flutter app for Fresh Pantry.

Required Dart defines for backend-enabled runs:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `FRESH_PANTRY_API_BASE_URL` defaults to `https://api.fresh-pantry.kunish.eu.org`
- `SENTRY_DSN` defaults to the Fresh Pantry Sentry project DSN
- `SENTRY_TRACES_SAMPLE_RATE` defaults to `1.0`
- `SENTRY_REPLAY_SESSION_SAMPLE_RATE` defaults to `1.0`
- `SENTRY_REPLAY_ON_ERROR_SAMPLE_RATE` defaults to `1.0`
- `SENTRY_ENVIRONMENT` is optional

Validation:

```bash
flutter analyze
flutter test
```

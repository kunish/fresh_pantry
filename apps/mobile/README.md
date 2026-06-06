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

## Sentry 符号上传 (dSYM / Dart 符号 / 源码)

发布版的原生帧默认显示为 `<redacted>`，因为 Sentry 缺少 iOS dSYM。crash 与
AppHang 想符号化到具体代码，需在构建后上传调试符号。配置在 `pubspec.yaml` 的
`sentry:` 块（org/project），认证走环境变量，**不要把 token 写进仓库**。

token 需 `project:releases` 权限（只读 token 无法上传）：在
Sentry → Settings → Auth Tokens 新建后导出：

```bash
export SENTRY_AUTH_TOKEN=<project:releases scope token>
```

构建并上传（`--split-debug-info` 让 Dart 帧也能符号化；不混淆——开源代码
无 `--obfuscate` 的必要，且少一份 symbol map 依赖更鲁棒）：

```bash
flutter build ipa --split-debug-info=build/debug-info
dart run sentry_dart_plugin
```

`dart run sentry_dart_plugin` 会上传 iOS dSYM 与 `build/debug-info` 下的 Dart
符号，并把 Dart 源码一并打包上传（`pubspec.yaml` 的 `upload_sources: true`），
让 Sentry 堆栈直接显示出错行的源码上下文——开源仓库源码本就公开，无泄露顾虑。
（`upload_source_maps` 仅用于 Flutter Web，本项目只发 iOS，故保持关闭。）
**发版 CI 已自动做这一步**（见 `.github/workflows/release.yml`）：仅需在仓库
Secrets 配置 `SENTRY_AUTH_TOKEN`（`project:releases` 权限）。

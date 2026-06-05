# TestFlight 自动发布(release-please)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `kunish/fresh_pantry` 在 Conventional Commits 驱动下自动 bump 版本、生成 CHANGELOG,并在 Release PR 合并后自动构建签名并上传 iOS 到 TestFlight。

**Architecture:** 单个 GitHub Actions workflow `release.yml`(push main 触发)三段 job 串联:① `release-please-action@v4`(ubuntu)维护/落地 Release;② gate(ubuntu)`flutter analyze`+`flutter test` 质量门禁;③ testflight(macOS)用 ASC API Key 自动签名,`xcodebuild archive` →(纯净 PATH)`-exportArchive` → `altool` 上传。job② / job③ 仅在 `releases_created==true` 时跑。

**Tech Stack:** GitHub Actions、googleapis/release-please-action@v4、subosito/flutter-action@v2、maxim-lobanov/setup-xcode@v1、Flutter 3.44.1、xcodebuild、xcrun altool、App Store Connect API Key。

**验证策略(CI/配置类计划,非传统 TDD):** 每个文件 task 用本地静态校验作为「红绿」——JSON 用 `jq`、plist 用 `plutil -lint`、workflow 用 `actionlint`。真正的运行时行为(release-please 开 PR、CI 构建上传)只能在真实触发后观察,集中在最后的端到端 Task 7,由用户主导(涉及真实发布)。

---

## File Structure

| 文件 | 责任 | 操作 |
|---|---|---|
| `release-please-config.json` | release-please 包配置(dart release-type,包路径 apps/mobile) | 创建(仓库根) |
| `.release-please-manifest.json` | 各包当前版本基线 | 创建(仓库根) |
| `apps/mobile/ios/ExportOptions.plist` | CI 导出 IPA 的签名/方式配置 | 创建 |
| `.github/workflows/release.yml` | 三段式发布流水线 | 创建 |

不改动现有 app 代码。加密合规声明已于 commit `fee9b1b` 写入 Info.plist。

**前置依赖(实施前确认一次):**
- 本机已装 `gh`、`jq`、`actionlint`(下方 Task 0 安装/校验)。
- ASC API Key 三件套:Key ID `K9ZD53WDUR`、Issuer `86b89170-b4e7-476a-be04-695be19bb5bf`、`.p8` 位于 `~/.appstoreconnect/private_keys/AuthKey_K9ZD53WDUR.p8`(今天已就位)。

---

## Task 0: 安装并校验本地工具

**Files:** 无(环境准备)

- [ ] **Step 1: 校验/安装工具**

Run:
```bash
command -v gh jq actionlint || brew install gh jq actionlint
```
Expected: 三个命令都有路径输出;缺失的由 brew 装上。

- [ ] **Step 2: 校验 gh 已登录**

Run:
```bash
gh auth status
```
Expected: 显示已登录 github.com 账号 `kunish`。若未登录,提示用户在会话中执行 `! gh auth login`。

---

## Task 1: release-please 配置文件

**Files:**
- Create: `release-please-config.json`(仓库根)
- Create: `.release-please-manifest.json`(仓库根)

- [ ] **Step 1: 创建 release-please-config.json**

`release-please-config.json`:
```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    "apps/mobile": {
      "release-type": "dart",
      "changelog-path": "CHANGELOG.md",
      "bump-minor-pre-major": true
    }
  }
}
```

- [ ] **Step 2: 创建 .release-please-manifest.json**

`.release-please-manifest.json`:
```json
{
  "apps/mobile": "1.0.1"
}
```

- [ ] **Step 3: 校验 JSON 语法**

Run:
```bash
jq . release-please-config.json && jq . .release-please-manifest.json
```
Expected: 两个文件都被解析并回显,无 parse error。

- [ ] **Step 4: Commit**

```bash
git add release-please-config.json .release-please-manifest.json
git commit -m "ci: 添加 release-please 配置(apps/mobile, dart)"
```

---

## Task 2: CI 导出配置 ExportOptions.plist

**Files:**
- Create: `apps/mobile/ios/ExportOptions.plist`

- [ ] **Step 1: 创建 ExportOptions.plist**

`apps/mobile/ios/ExportOptions.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>62HCT6Q83X</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
```

- [ ] **Step 2: 校验 plist 语法**

Run:
```bash
plutil -lint apps/mobile/ios/ExportOptions.plist
```
Expected: `apps/mobile/ios/ExportOptions.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/ios/ExportOptions.plist
git commit -m "ci: 添加 App Store 导出配置(自动签名)"
```

---

## Task 3: workflow 骨架 + job① release-please

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: 创建 release.yml(仅 job①)**

`.github/workflows/release.yml`:
```yaml
name: release

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    outputs:
      release_created: ${{ steps.release.outputs.releases_created }}
    steps:
      - uses: googleapis/release-please-action@v4
        id: release
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

- [ ] **Step 2: 校验 workflow**

Run:
```bash
actionlint .github/workflows/release.yml
```
Expected: 无输出(actionlint 无发现即成功,退出码 0)。

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release.yml 接入 release-please"
```

---

## Task 4: job② 质量门禁(analyze + test)

**Files:**
- Modify: `.github/workflows/release.yml`(在 `release-please` job 之后追加 `gate` job)

- [ ] **Step 1: 实施前现状预检(本地)**

Run:
```bash
cd apps/mobile && flutter pub get && flutter analyze && flutter test
cd ../..
```
Expected: analyze 与 test 全过。**若有失败:** 门禁会拦截发布——先修复测试,或与用户确认是否临时把失败用例标记/跳过。不要为了过门禁而弱化测试。

- [ ] **Step 2: 在 release.yml 追加 gate job**

在 `release.yml` 的 `jobs:` 下、`release-please` job 之后追加:
```yaml
  gate:
    needs: release-please
    if: ${{ needs.release-please.outputs.release_created == 'true' }}
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/mobile
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.1
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

- [ ] **Step 3: 校验 workflow**

Run:
```bash
actionlint .github/workflows/release.yml
```
Expected: 无输出,退出码 0。

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: 发版前置 analyze+test 门禁"
```

---

## Task 5: job③ 构建签名上传 TestFlight

**Files:**
- Modify: `.github/workflows/release.yml`(在 `gate` job 之后追加 `testflight` job)

- [ ] **Step 1: 在 release.yml 追加 testflight job**

在 `release.yml` 的 `jobs:` 下、`gate` job 之后追加:
```yaml
  testflight:
    needs: gate
    runs-on: macos-15
    defaults:
      run:
        working-directory: apps/mobile
    env:
      ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.1
          channel: stable
          cache: true
      - name: Install ASC API key
        run: |
          mkdir -p "$HOME/.appstoreconnect/private_keys"
          printf '%s' "${{ secrets.ASC_API_KEY_P8 }}" > "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
      - run: flutter pub get
      - name: Compute build number
        id: bn
        run: echo "build_number=$(date -u +%Y%m%d%H%M)" >> "$GITHUB_OUTPUT"
      - name: Generate Flutter iOS config (writes Generated.xcconfig)
        run: flutter build ios --release --config-only --build-number=${{ steps.bn.outputs.build_number }}
      - name: Archive (API key auto-signing)
        run: |
          xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
            -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
            -archivePath build/ios/archive/Runner.xcarchive \
            archive \
            -allowProvisioningUpdates \
            -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8" \
            -authenticationKeyID "$ASC_KEY_ID" \
            -authenticationKeyIssuerID "$ASC_ISSUER_ID"
      - name: Export IPA (clean PATH avoids Homebrew GNU rsync "Copy failed")
        run: |
          env PATH="/usr/bin:/bin:/usr/sbin:/sbin" xcodebuild -exportArchive \
            -archivePath build/ios/archive/Runner.xcarchive \
            -exportPath build/ios/ipa \
            -exportOptionsPlist ios/ExportOptions.plist \
            -allowProvisioningUpdates \
            -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8" \
            -authenticationKeyID "$ASC_KEY_ID" \
            -authenticationKeyIssuerID "$ASC_ISSUER_ID"
      - name: Upload to TestFlight (one retry)
        run: |
          IPA="$(ls build/ios/ipa/*.ipa | head -1)"
          echo "Uploading: $IPA"
          for attempt in 1 2; do
            if xcrun altool --upload-app -f "$IPA" -t ios \
                 --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"; then
              echo "upload ok"; exit 0
            fi
            echo "upload attempt $attempt failed; retrying in 30s"; sleep 30
          done
          echo "upload failed after retries"; exit 1
```

- [ ] **Step 2: 校验 workflow**

Run:
```bash
actionlint .github/workflows/release.yml
```
Expected: 无输出,退出码 0。(若提示 `secrets`/`shellcheck` 警告,逐条核对;`SC2086` 对受控变量可忽略。)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: macOS 构建并上传 TestFlight(API key 自动签名)"
```

---

## Task 6: 配置 GitHub Secrets

**Files:** 无(仓库 Secrets,经 `gh` 写入)

- [ ] **Step 1: 写入三个 secret**

Run(`ASC_API_KEY_P8` 从文件读以保留 PEM 换行):
```bash
gh secret set ASC_KEY_ID --body "K9ZD53WDUR"
gh secret set ASC_ISSUER_ID --body "86b89170-b4e7-476a-be04-695be19bb5bf"
gh secret set ASC_API_KEY_P8 < "$HOME/.appstoreconnect/private_keys/AuthKey_K9ZD53WDUR.p8"
```
Expected: 每条输出 `✓ Set Actions secret ... for kunish/fresh_pantry`。

- [ ] **Step 2: 校验**

Run:
```bash
gh secret list
```
Expected: 列出 `ASC_API_KEY_P8`、`ASC_ISSUER_ID`、`ASC_KEY_ID` 三项。

---

## Task 7: 端到端验证(真实发布,用户主导)

**Files:** 无(触发真实流水线)

> 本 task 会产生真实 TestFlight 上传。先把 Task 1–6 的提交推送到 main。

- [ ] **Step 1: 推送已完成的 CI 配置**

Run:
```bash
git push origin main
```
Expected: push 成功。此次 push 触发 `release.yml`,`release-please` job 会创建一个 Release PR(`releases_created` 为 false,gate/testflight 不跑)。

- [ ] **Step 2: 观察 release-please 开出 Release PR**

Run:
```bash
gh pr list --label "autorelease: pending"
gh run list --workflow release.yml --limit 3
```
Expected: 出现一个标题形如 `chore(main): release apps/mobile x.y.z` 的 PR;workflow run 成功。
（若此前已有未发布的 feat/fix 提交,PR 会据此 bump;否则可造一条:`git commit --allow-empty -m "fix: 触发 release-please 首次发版"` 再 push。）

- [ ] **Step 3: 合并 Release PR**

Run(替换 `<PR>` 为上一步的编号):
```bash
gh pr merge <PR> --squash --admin
```
Expected: 合并成功。合并这次 push 再次触发 `release.yml`;这次 `release-please` 创建 GitHub Release(`releases_created==true`),gate → testflight 接力。

- [ ] **Step 4: 跟踪流水线**

Run:
```bash
gh run watch "$(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: gate 通过、testflight 的 archive/export/upload 步骤全绿,日志出现 `UPLOAD SUCCEEDED`。

- [ ] **Step 5: 确认 TestFlight 收到构建**

人工:在 App Store Connect → TestFlight 看到新 build,build 号为时间戳(如 `2026...`),版本号为 release-please 写入的 x.y.z;不再要求加密合规声明。

---

## Self-Review(已执行)

- **Spec coverage:** release-please 配置(T1)、ExportOptions(T2)、job①②③(T3/T4/T5)、Secrets(T6)、build number 时间戳(T5 Step1)、门禁(T4)、端到端验收(T7)——spec 各节均有对应 task。
- **Placeholder scan:** 无 TBD/TODO;每个文件 task 给出完整文件内容与确切校验命令。
- **一致性:** secret 名(`ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_API_KEY_P8`)、p8 路径、`releases_created` output 名在 T3/T4/T5/T6 全程一致;archive 段保留 flutter 所需 PATH、仅 export 段用纯净 PATH 的区分已在 T5 明确。
- **已知软点:** macOS runner 的 Xcode 用 `latest-stable`、`flutter build ios --config-only` 生成 xcconfig——首跑若报错,按日志在 T5 微调(job 支持 re-run),不影响其余 task。

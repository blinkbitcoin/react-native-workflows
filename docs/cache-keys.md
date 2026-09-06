# Cache keys

Every cache this family writes, what produces the key, and what invalidates it.
Bumping the `native-cache-version` input (default `v1`) invalidates every
native cache at once.

## The native dependency hash

`hash` is a 16-hex digest computed by `scripts/ci/native-hash.sh` (wrapped by
`scripts/ci/native-keys.sh`, exposed by the `native-key` composite action). It
is deliberately computable *before* `pnpm install`, so a cache lookup never
waits on a dependency install. It folds together:

1. From `pnpm-lock.yaml`, `importers["."]`: every runtime dependency, plus the
   devDependencies whose name matches
   `^(expo|@expo/|react-native|@react-native|@react-native-community|@config-plugins/|patch-package)`,
   rendered as `name@version` (read with `yq`).
2. A `shasum -a 256` per file (not `hashFiles`) over two sets: the
   **root-level only** (`find -maxdepth 1`) matches of `app.config.*`,
   `app.json`, `Gemfile.lock`, `.mise.toml`, `google-services.json`,
   `GoogleService-Info.plist`; and every file found **recursively** under
   `plugins/`, `modules/` and `patches/`. A nested `app.config.ts` is
   deliberately not picked up — if you have one, add it via
   `native-extra-globs`.
3. The contents of every file matched by the `native-extra-globs` input
   (`e2e.yml` input of the same name, threaded into the `native-key` action) —
   space-separated, consumer-relative shell globs, e.g.
   `fastlane/*.rb android/keystores/*`. No recursive `**` (these scripts run
   under macOS's bash 3.2, which has no `globstar`). The glob *string* itself is
   folded in too, so changing the patterns also invalidates the caches.

## Keys

| Cache | Key | Produced by | Used in |
| --- | --- | --- | --- |
| iOS app (`.app` + `ios/*.xcworkspace`) | `ios-app-{ver}-{os}-{arch}-xcode{x}-{hash}` (exact; `{x}` is the `xcode` input or `default`) | `native-key` action → `scripts/ci/native-keys.sh` (`ios-key` output) | `e2e.yml` job `build-ios`, `actions/cache/restore@v6` + `actions/cache/save@v6` |
| Android debug APK | `android-apk-{ver}-{hash}` (exact) | `native-key` action → `scripts/ci/native-keys.sh` (`android-key` output) | `e2e.yml` job `build-android`, restore + save |
| CocoaPods (`ios/Pods`, `~/Library/Caches/CocoaPods`) | `pods-{os}-{hash}`, restore-keys prefix `pods-{os}-` | `native-key` action → `scripts/ci/native-keys.sh` (`pods-key` output) | `e2e.yml` job `build-ios`, `actions/cache@v6` (a prefix hit is fine: `pod install` reconciles) |
| pnpm store | `pnpm-{os}-{hashFiles('**/pnpm-lock.yaml')}`, restore-keys prefix `pnpm-{os}-` | `setup` action (path from `scripts/ci/pnpm-store-path.sh`) | every workflow that runs `setup` |
| Maestro CLI (`~/.maestro`) | `maestro-{os}-{version}` | `maestro` action (version = its `version` input, pinned to `MAESTRO_VERSION`) | `e2e.yml` jobs `ios`, `android` |
| Android system image | `sysimg-v1-{api}-default-x86_64` | `e2e.yml` job `android` (literal key; `{api}` = `android-api-level`) | `actions/cache@v6` over `$ANDROID_SDK_DIR/system-images/android-{api}` |
| AVD + adb keys | `avd-v1-{api}-x86_64-default-hidedialogs` | `e2e.yml` job `android` (literal key) | `actions/cache@v6` over `~/.android/avd/*`, `~/.android/adb*`; a miss bakes a snapshot via `scripts/e2e/android-emulator.sh snapshot-bake` |
| Playwright browsers | `playwright-{os}-{pwversion}` | `web.yml` job `playwright` (version from `scripts/web/playwright-cache-key.sh`, which wraps `scripts/web/playwright-version.sh`) | `web.yml` playwright job |
| Gradle | managed by `gradle/actions/setup-gradle` | that action | `e2e.yml` job `build-android` (`cache-read-only` off main) |
| mise tools | managed by `jdx/mise-action` (`cache: true`) | that action | `setup` and `native-key` actions |

Notes:

- The `-hidedialogs` suffix on the AVD key is a content marker, not a value read
  from anywhere: the cached snapshot has `hide_error_dialogs 1` and
  `anr_show_background 0` baked in. Change what `snapshot-bake` writes and bump
  the suffix.
- `{ver}` is the `native-cache-version` input, `{os}`/`{arch}` come from the
  runner, and `{hash}` is the native dependency hash above.
- The iOS app cache carries the generated `ios/*.xcworkspace` alongside the
  built `.app` because `scripts/native/ios-pack.sh` resolves the Xcode scheme
  from the workspace, and on a cache hit no `expo prebuild` has run.

<!--
Env contract for scripts/native/* and scripts/e2e/*. Every variable is optional
and defaulted; a consumer sets only what differs. Task 9 copies this table into
docs/consumer-guide.md - keep the two in sync by copying, not by rewording.
-->

# Native build and E2E device scripts

Two families, one env contract:

- `scripts/native/*` turns a checkout into a runnable app (`prebuild.sh`, `pods.sh`, `ios-build.sh`, `ios-pack.sh`, `android-build.sh`).
- `scripts/e2e/*` drives a device and the Maestro suite (`metro-start.sh`, `metro-wait.sh`, `ios-simulator.sh`, `android-emulator.sh`, `app-launch.sh`, `maestro-bound.sh`, `ios-maestro.sh`, `android-maestro.sh`, `collect-forensics.sh`).

All of them run from the repo that hosts these scripts and act on the *consumer*
checkout resolved by `consumer_root` (`$GITHUB_WORKSPACE/$WORKING_DIRECTORY`).

## Prerequisites

On the machine running these scripts: `bash`, `pnpm`, `curl`, `jq`
(`ios-simulator.sh pick` parses `simctl list -j`), `yq` (via
`scripts/lib/expo-config.sh`), and `maestro` on `PATH` or in `~/.maestro/bin`
(`scripts/ci/maestro-install.sh` puts it there). Platform-specific: `xcodebuild`
+ `xcrun` and CocoaPods (`pod`, or `bundle` when the consumer has a `Gemfile`)
for iOS; `adb` and a JDK for Android. Optional: `xcbeautify` or `xcpretty` to
format the Xcode log, `timeout`/`gtimeout` for `maestro-bound.sh` (there is a
pure-bash fallback).

## Env contract

| Variable | Default | Meaning |
| --- | --- | --- |
| `RNW_PLATFORM` | (none) | `ios` or `android`, used when a script is called without its positional platform argument. |
| `RNW_XCODE` | (none) | Xcode version; `ios-build.sh` runs `sudo xcode-select -s /Applications/Xcode_$RNW_XCODE.app` when set. |
| `RNW_APP_ID` | `expo config` → `ios.bundleIdentifier` / `android.package` | Application id under test. The Expo config already carries any variant suffix, so nothing is appended. |
| `RNW_DEV_CLIENT` | `true` | Launch through the `expo-development-client` deep link and start Metro with `--dev-client`. Set `false` for a standalone build. |
| `RNW_MAESTRO_FLOWS` | `.maestro` | Flows directory, consumer-relative. `config.yaml` inside it is passed as `--config` when present. |
| `RNW_MAESTRO_INCLUDE_TAGS` | (none) | Passed as `--include-tags` only when set; the consumer's `config.yaml` normally carries `includeTags` already. |
| `RNW_MAESTRO_EXCLUDE_TAGS` | (none) | Passed as `--exclude-tags` only when set. |
| `RNW_SUITE_TIMEOUT_MINUTES` | `10` | Per-attempt bound enforced inside the script (`maestro-bound.sh`), so forensics still run on a hang. |
| `RNW_METRO_PORT` | `8081` | Metro port; also the port reversed into the Android emulator. |
| `RNW_OUT` | `${RUNNER_TEMP:-/tmp}/rnw` | Every artifact this family writes: `metro.log`, `metro.pid`, `sim-udid`, `<scheme>.app.tar`, `maestro/`, `forensics/`, videos. |
| `RNW_E2E_SETUP_SCRIPT` | (none) | Consumer-relative script run before the suite (e.g. start a mock API). A missing file is fatal. |
| `RNW_E2E_TEARDOWN_SCRIPT` | (none) | Consumer-relative script run after the suite, pass or fail. |
| `RNW_ANDROID_ABIS` | `x86_64` | `-PreactNativeArchitectures` for `android-build.sh`. CI emulators are x86_64; set `arm64-v8a` to run against an Apple-silicon emulator locally. |

`$RNW_OUT/run-start` is stamped once, by whichever script sources
`scripts/lib/e2e-env.sh` first; `collect-forensics.sh` selects iOS crash reports
newer than it.

`RNW_SIM_UDID` is produced, not consumed: `ios-simulator.sh pick` writes it to
`$GITHUB_ENV`, to `$GITHUB_OUTPUT` as `udid`, and to `$RNW_OUT/sim-udid` so a
later step (or a local shell) finds the device without env plumbing.

**`APP_VARIANT` must not be `production` for E2E.** The app id, the scheme and
the flows all follow the development variant; a production config produces an app
id the flows' `${APP_ID}` never matches.

## Order

iOS:

```
prebuild.sh ios → pods.sh → ios-build.sh → ios-pack.sh
ios-simulator.sh pick → metro-start.sh → ios-simulator.sh wait
  → ios-simulator.sh install "$RNW_OUT/<scheme>.app.tar"
  → metro-wait.sh ios → app-launch.sh ios → ios-maestro.sh
  → collect-forensics.sh ios
```

Android (`android-maestro.sh` is the single-line entry for
`reactivecircus/android-emulator-runner`'s `script:` and does the last five
steps itself):

```
prebuild.sh android → android-build.sh
metro-start.sh → metro-wait.sh android
  → android-maestro.sh   # prepare, record, launch, suite, forensics
```

## Notes

- `maestro-bound.sh` is sourced, not executed: `bounded_maestro SECONDS CMD...`
  returns 124 on a timeout. It uses `timeout`/`gtimeout` when present and a
  pure-bash watchdog otherwise (a stock Mac has neither).
- The Maestro suite is retried once on a real failure, never after a 124: a hung
  driver only burns the step's `timeout-minutes` a second time.
- `collect-forensics.sh` always exits 0.
- Stop Metro with `kill -TERM -"$(cat "$RNW_OUT/metro.pid")"` (note the leading
  `-`: the pid is a process-group id). Killing the pid alone reaps the pnpm
  wrapper and leaves node holding the port.
- The Xcode scheme comes from `expo-config.sh ios.scheme-name` but is validated
  against the generated `ios/*.xcworkspace`; the workspace wins and a mismatch
  prints a `::warning::`.

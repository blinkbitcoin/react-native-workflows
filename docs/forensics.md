# Forensics

What `e2e.yml` and `web.yml` upload when something goes wrong, and how to read
it. Every forensics step runs with `if: always()`, so it uploads on both pass
and fail (a green run's artifact is usually small and worth skimming anyway).

## Where it comes from

`scripts/e2e/collect-forensics.sh <ios|android>` always exits `0` (a forensics
failure must never fail the job) and writes into `$RNW_OUT/forensics`:

- `metro.log` — the bundler's full stdout/stderr for the run.
- `*.mp4` — the screen recording (`ios-simulator.sh record start|stop` /
  `android-emulator.sh record start|stop`), started right before the app
  launches and stopped in the `always()` teardown step.
- iOS only: crash reports (`*.ips`, `*.crash`) copied from
  `~/Library/Logs/DiagnosticReports`, filtered to files newer than
  `$RNW_RUN_START` (a timestamp file stamped once per job by whichever script
  sources `scripts/lib/e2e-env.sh` first) so a stale crash from a previous job
  on the same runner never shows up. If that stamp is missing for some reason
  the fallback is "modified in the last 60 minutes".
- Android only: `logcat.txt` (full buffer) and `logcat-crash.txt` (the crash
  buffer). The step also prints two `::group::` blocks straight into the job
  log so you don't have to download anything for the common case: the last 200
  lines of the crash buffer, and the last 200 lines of `logcat.txt` matching
  `ReactNativeJS|AndroidRuntime|FATAL|Fatal signal|lowmemorykiller|has died|app died`.

The `forensics` composite action then uploads `$RNW_OUT/forensics` (or
`playwright-report/` for the web workflow) as an artifact and calls
`scripts/ci/artifact-summary.sh`, which writes a table with the artifact's
download URL and, when a `junit` path was given, the pass/fail/total counts
parsed out of it, straight into the job's step summary — so the first thing to
check is the **Summary** tab of the run, not the artifact.

## Reading the Maestro debug output

`ios-maestro.sh` / `android-maestro.sh` pass Maestro:

```
--debug-output "$RNW_OUT/maestro" --flatten-debug-output --format junit --output "$RNW_OUT/maestro/junit.xml"
```

Inside the `forensics-ios` / `forensics-android` artifact you'll find:

- `junit.xml` — machine-readable pass/fail per flow; this is what
  `artifact-summary.sh` totals for the step summary.
- `--flatten-debug-output` puts every flow's debug files (device logs,
  per-command screenshots, the recorded command hierarchy) directly in
  `maestro/` instead of nested per-run subdirectories — the naming is
  `<flowName>-<commandIndex>-<label>.png`/`.txt`; sort by flow name to follow
  one flow's timeline.
- Maestro writes a screenshot per command it executes, so scanning the
  numbered PNGs in flow order shows the UI state right up to the failing
  command without needing to scrub the video.

## The suite retry and what it means for forensics

Both platform scripts retry the suite exactly once on a **real** failure
(`status != 0 && status != 124`) — a timeout (`124`, from `maestro-bound.sh`)
is never retried, because a hung driver would just burn the timeout twice. The
recording and forensics you get are from **whichever attempt is the exit
status of the step** — the retry replaces the first attempt's Maestro debug
output on disk before `collect-forensics.sh` runs, so if the suite failed then
passed on retry, the uploaded video/log are the retry's, not the failure's. If
you need to see the first attempt's flake, re-run with
`maestro-include-tags`/`exclude-tags` narrowed to the flaky flow, or watch the
job log directly — the `::group::` blocks for both attempts stay in the raw
log even though the artifact only carries the final attempt's files.

## Video

- iOS: `xcrun simctl io <udid> recordVideo`, started right after install, wait
  and Metro warm-up, stopped in the always-run teardown.
- Android: `adb emu screenrecord` (chunked internally by the emulator to avoid
  the ~3-minute single-file cap); `android-emulator.sh record stop` pulls and
  concatenates chunks before `collect-forensics.sh` copies the `.mp4` out.
- The video covers install → launch → suite, so a UI assertion failure near
  the end of a long suite is often faster to diagnose by scrubbing to the last
  30 seconds of the video than by replaying every Maestro screenshot.

## web.yml (Playwright)

`web.yml`'s `playwright` job forensics step uploads `playwright-report/` (Playwright's
own HTML report, traces and screenshots) as `playwright-report`; open
`index.html` locally (`npx playwright show-report <dir>`) for the interactive
trace viewer — it's more useful than the individual PNGs for a web failure.

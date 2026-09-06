#!/usr/bin/env bash
# Start Metro in the background so its boot overlaps the rest of the setup;
# metro-wait.sh awaits it. nohup + a pid file so the process survives the step
# that started it (each GitHub Actions step is its own shell) and can be killed
# deterministically at the end of the job.
# Log: $RNW_OUT/metro.log  Pid: $RNW_OUT/metro.pid
# Usage: metro-start.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

require_cmd pnpm
root="$(consumer_root)"
cd "$root"

args=(expo start --port "$RNW_METRO_PORT")
# A dev-client build is not an Expo Go client: without the flag `expo start`
# advertises an exp:// URL the installed app cannot open.
[ "$RNW_DEV_CLIENT" = "true" ] && args+=(--dev-client)

# Job control on: the background job then leads its own process group, so
# `kill -TERM -$(cat metro.pid)` takes the whole tree down. Killing the pid
# alone only reaps the pnpm wrapper and leaves node holding the port.
set -m
CI=1 nohup pnpm exec "${args[@]}" > "$RNW_OUT/metro.log" 2>&1 &
pid=$!
set +m
printf '%s\n' "$pid" > "$RNW_OUT/metro.pid"
log "Metro starting (pid $pid, port $RNW_METRO_PORT, log $RNW_OUT/metro.log)"
log "stop it with: kill -TERM -$pid"

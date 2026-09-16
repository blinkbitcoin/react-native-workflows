#!/usr/bin/env bash
# Publish the caller's build-env into $GITHUB_ENV. Runs before prebuild, the
# lanes and the notes generator, so everything downstream sees the same values.
# See scripts/lib/build-env.sh for the validation rules.
# Usage: build-env.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/build-env.sh"

group "build-env"
workflows_publish_build_env
endgroup

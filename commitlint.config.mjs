// Conventional Commits with a closed scope list. The commit-msg hook and
// pr-title.yml lint against this same file, because a squash merge takes the
// PR title as the commit message on main.
//
// The list is kept sorted and duplicate-free (test/hooks.bats checks both) and
// is drawn from the real tree: one scope per directory a change can land in.
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [
      2,
      'always',
      [
        'actions', // .github/actions/**  composite actions
        'checks', // scripts/checks/**   + checks.yml
        'ci', // scripts/ci/**       + self-ci.yml
        'deps', // dependabot and pinned tool bumps
        'docs', // docs/** and README
        'e2e', // scripts/e2e/**      + e2e.yml
        'lib', // scripts/lib/**      shared bash helpers
        'native', // scripts/native/**   prebuild, pods, platform builds
        'ota', // scripts/ota/**      + expo-ota-publish.yml
        'release', // scripts/release/**  + github-release.yml, fastlane-lane.yml
        'self', // scripts/self/**     + self-*.yml (this repo's own CI)
        'test', // test/**             the bats suite and its fixtures
        'tooling', // Makefile, .mise.toml, hooks, lint config
        'web', // scripts/web/**      + web.yml
        'workflows', // .github/workflows/** as a shape, and the consumer contract
      ],
    ],
    // Pasted logs, URLs and trailers routinely exceed 100 columns; the subject
    // line is the part worth policing.
    'body-max-line-length': [0],
    'footer-max-line-length': [0],
  },
};

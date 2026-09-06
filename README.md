# react-native-workflows

Reusable GitHub Actions workflows and bash scripts for building, testing, and
releasing React Native apps, consumed by `react-native-mobile-template` and
similar projects.

Consumer guide coming.

## After push

- Every job self-checks-out this repo into `.rnw/` via
  `repository: ${{ job.workflow_repository }}`, `ref: ${{ job.workflow_sha }}`
  (the job context's fields for the reusable workflow file that defines the
  current job, not the caller). **After pushing any change to a workflow under
  `.github/workflows/`, watch the first real CI run on a consumer and confirm
  the `.rnw` checkout step actually resolves to
  `blinkbitcoin/react-native-workflows` at the ref/sha that defines the
  running job** — a regression here would silently check out the wrong repo
  (or the consumer's own repo) into `.rnw` and break every downstream step
  that references `$RNW`.

# sway-action

Run [`sway`](https://github.com/tenseleyFlow/sway) against a PEFT
adapter on every pull request, post the report as a PR comment, exit
non-zero on regression. Three lines of YAML.

```yaml
- uses: tenseleyflow/sway-action@v0.1.0
  with:
    spec-path: sway.yaml
```

## What it does

1. Bootstraps a Python venv and installs `dlm-sway[hf]` (pinned).
2. Runs `sway gate <spec-path>` and captures the JSON report.
3. Renders the report as markdown and posts it as a PR comment —
   editing the prior comment in place on subsequent runs so rebases
   don't spam the conversation.
4. Uploads the JSON + markdown report as a workflow artifact.
5. Exits non-zero according to the `fail-on` policy.

The action is intentionally a thin wrapper. Anything more than the
inputs below belongs in your own workflow.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `spec-path` | _required_ | Path to your `sway.yaml` (relative to the repo root). |
| `fail-on` | `fail` | One of `fail` (only hard failures fail the action), `warn` (warns also fail), or `never`. |
| `comment-on-pr` | `true` | Post / edit the markdown report as a PR comment. |
| `upload-artifact` | `true` | Upload the JSON + markdown reports as a workflow artifact. |
| `sway-version` | `0.1.0` | The `dlm-sway` version to install. Pin this if you want action upgrades not to silently change sway behavior. |
| `python-version` | `3.11` | Python interpreter version for the sway venv. |

## Outputs

| Output | Description |
| --- | --- |
| `sway-score` | Composite score (0.0 – 1.0) parsed from the JSON report. Empty when the run errored. |
| `verdict` | `pass`, `warn`, `fail`, or `error`. |
| `report-path` | Filesystem path to the JSON report inside the runner workspace. |

## Permissions

The action uses `GITHUB_TOKEN` to post / edit the PR comment. Your
workflow needs:

```yaml
permissions:
  contents: read
  pull-requests: write   # only when comment-on-pr=true
```

If you set `comment-on-pr: 'false'` you can drop the
`pull-requests: write` permission.

## A complete workflow

```yaml
name: sway
on:
  pull_request:
    paths:
      - "**/*.dlm"
      - "**/sway.yaml"

permissions:
  contents: read
  pull-requests: write

jobs:
  sway:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: tenseleyflow/sway-action@v0.1.0
        with:
          spec-path: sway.yaml
```

## Caching

The action caches the sway venv keyed on
`(runner.os, python-version, sway-version)`. Reruns on the same
runner image reuse the torch wheels — first run takes ~2 minutes,
cached runs ~10 seconds.

## Why this exists

You can absolutely call `sway gate` from a hand-written workflow.
The action exists to:

- **Lower onboarding friction** — three lines vs thirty.
- **Standardize the PR comment format** so adopters' PRs all show the
  same recognizable verdict sticker.
- **Ship the edit-in-place comment behavior by default** — handling
  rebases-without-spam from scratch is the one annoying bit of
  workflow boilerplate.

If you outgrow the wrapper, lift the
[`entrypoint.sh`](src/entrypoint.sh) and
[`post-comment.js`](src/post-comment.js) into your own workflow —
they're short and unsurprising.

## License

MIT — see [LICENSE](LICENSE).

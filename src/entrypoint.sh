#!/usr/bin/env bash
# entrypoint.sh — bootstrap a venv, install dlm-sway, run the suite, emit
# step outputs the composite action's later steps consume.
#
# Required env (set by action.yml):
#   SWAY_ACTION_PATH  — github.action_path (where this script lives)
#   SWAY_SPEC_PATH    — user-supplied path to sway.yaml
#   SWAY_FAIL_ON      — fail / warn / never
#   SWAY_VERSION      — pinned dlm-sway version
#
# Outputs (written to $GITHUB_OUTPUT):
#   sway-score     — composite float (0.0 – 1.0); empty when run errored
#   verdict        — pass / warn / fail / error
#   report-path    — absolute path to the JSON report
#   markdown-path  — absolute path to the markdown report

set -euo pipefail

: "${SWAY_ACTION_PATH:?must be set by action.yml}"
: "${SWAY_SPEC_PATH:?spec-path input is required}"
: "${SWAY_FAIL_ON:=fail}"
: "${SWAY_VERSION:=0.1.0}"
: "${GITHUB_OUTPUT:?must be set by GitHub Actions}"

VENV="${SWAY_ACTION_PATH}/.venv"
PY="${VENV}/bin/python"

if [[ ! -x "${PY}" ]]; then
  echo "::group::Bootstrap sway venv (dlm-sway==${SWAY_VERSION})"
  python -m venv "${VENV}"
  "${PY}" -m pip install --upgrade pip
  # `[hf]` pulls torch + transformers + peft. Worst-case install is ~2
  # minutes on a fresh runner; the actions/cache step in action.yml
  # short-circuits this on subsequent runs keyed on (os, python, version).
  "${PY}" -m pip install "dlm-sway[hf]==${SWAY_VERSION}"
  echo "::endgroup::"
else
  echo "Reusing cached sway venv at ${VENV}"
fi

REPORT_DIR="${RUNNER_TEMP:-/tmp}/sway-action-${GITHUB_RUN_ID:-local}"
mkdir -p "${REPORT_DIR}"
JSON_PATH="${REPORT_DIR}/sway.json"
MD_PATH="${REPORT_DIR}/sway.md"

# Always emit the four output keys before exiting so later steps in the
# composite can short-circuit cleanly (e.g. "skip artifact upload when
# report-path is empty"). The values are set incrementally — verdict/
# score get filled in once we have a report; report-path is set as
# soon as we know where it'll land.
write_output() {
  local key="$1"
  local val="$2"
  printf '%s=%s\n' "${key}" "${val}" >> "${GITHUB_OUTPUT}"
}

write_output "report-path" "${JSON_PATH}"
write_output "markdown-path" "${MD_PATH}"

echo "::group::sway gate ${SWAY_SPEC_PATH}"
GATE_EXIT=0
"${PY}" -m dlm_sway gate "${SWAY_SPEC_PATH}" \
  --report "${JSON_PATH}" || GATE_EXIT=$?
echo "::endgroup::"

if [[ ! -s "${JSON_PATH}" ]]; then
  # Gate didn't produce a report (network failure during model load,
  # spec validation error, etc.). Surface as `verdict=error` so the
  # PR comment still renders something explanatory and the action
  # exits non-zero regardless of fail-on.
  write_output "verdict" "error"
  write_output "sway-score" ""
  printf '# sway: error\n\nThe gate did not produce a report. See the workflow logs for details.\n' \
    > "${MD_PATH}"
  exit "${GATE_EXIT:-1}"
fi

echo "::group::sway report --format md"
"${PY}" -m dlm_sway report "${JSON_PATH}" --format md > "${MD_PATH}" || {
  echo "::warning::sway report --format md failed; falling back to a stub" >&2
  printf '# sway report\n\nReport rendering failed; see %s for raw JSON.\n' "${JSON_PATH}" \
    > "${MD_PATH}"
}
echo "::endgroup::"

# Parse score + verdict from the JSON report. Use python (already in
# the venv) instead of jq so the action has no extra system deps.
SUMMARY="$("${PY}" - <<PYEOF
import json, sys
with open("${JSON_PATH}", "r", encoding="utf-8") as f:
    data = json.load(f)

# Top-level verdict: 'fail' if any probe fails, 'warn' if any warns,
# else 'pass'. Mirrors how the sway CLI's gate command computes its
# exit code so the PR comment matches the action's exit behavior.
verdicts = [p.get("verdict", "") for p in data.get("probes", [])]
if "fail" in verdicts or "error" in verdicts:
    verdict = "fail"
elif "warn" in verdicts:
    verdict = "warn"
else:
    verdict = "pass"

score = data.get("score", {}).get("overall")
score_str = f"{score:.4f}" if isinstance(score, (int, float)) else ""

print(f"{verdict}|{score_str}")
PYEOF
)"

VERDICT="${SUMMARY%%|*}"
SCORE="${SUMMARY##*|}"

write_output "verdict" "${VERDICT}"
write_output "sway-score" "${SCORE}"

echo "sway: verdict=${VERDICT} score=${SCORE}"

# Translate the user's fail-on input into a final exit code.
case "${SWAY_FAIL_ON}" in
  never)
    exit 0
    ;;
  warn)
    [[ "${VERDICT}" == "pass" ]] && exit 0
    exit 1
    ;;
  fail|*)
    [[ "${VERDICT}" == "fail" ]] && exit 1
    # Pass and warn both clear when fail-on=fail (default).
    exit 0
    ;;
esac

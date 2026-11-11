#!/bin/bash
# Tests the GitHub Action wrapper. The fake waxen records argv and exit
# status; the script under test is action/diagnose.sh, not a second diagnosis.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/action/diagnose.sh"
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/waxen-action-XXXXXX")
trap 'rm -rf "$WORKDIR"' EXIT

fake_bin="$WORKDIR/waxen"
args_file="$WORKDIR/args"
report="$WORKDIR/report.json"
output="$WORKDIR/github-output"
target="$WORKDIR/Valid.app"
summary="$WORKDIR/summary"
mkdir -p "$target"

cat >"$fake_bin" <<'FAKE'
#!/bin/sh
status="${WAXEN_FAKE_STATUS:-1}"
if printf '%s\n' "$@" | grep -q -- '--share'; then
  printf '### waxen: Don'"'"'t open this app.\n\n- **Verdict:** `%s`\n' "${WAXEN_FAKE_VERDICT:-tampered}"
  exit "$status"
fi
printf '%s\n' "$@" >"${WAXEN_FAKE_ARGS:?}"
if printf '%s\n' "$@" | grep -q -- '--json'; then
  printf '%s\n' "${WAXEN_FAKE_JSON}"
else
  printf '%s\n' "${WAXEN_FAKE_TEXT:-Launch status: BLOCKED}"
fi
exit "$status"
FAKE
chmod 755 "$fake_bin" "$SCRIPT"

run_action() {
  rm -f "$args_file" "$report" "$output" "$summary"
  fake_json='{"launchStatus":"blocked"}'
  if [ -n "${WAXEN_FAKE_JSON:-}" ]; then
    fake_json="$WAXEN_FAKE_JSON"
  fi
  WAXEN_PATH="$target" \
    WAXEN_BIN="$fake_bin" \
    WAXEN_JSON="${WAXEN_JSON:-true}" \
    WAXEN_REPORT_PATH="$report" \
    WAXEN_FAIL_ON_BLOCKER="${WAXEN_FAIL_ON_BLOCKER:-true}" \
    WAXEN_FAIL_ON_ERROR="${WAXEN_FAIL_ON_ERROR:-true}" \
    WAXEN_INSTALL=false \
    WAXEN_FAKE_ARGS="$args_file" \
    WAXEN_FAKE_STATUS="${WAXEN_FAKE_STATUS:-1}" \
    WAXEN_FAKE_JSON="$fake_json" \
    WAXEN_FAKE_VERDICT="${WAXEN_FAKE_VERDICT:-tampered}" \
    GITHUB_OUTPUT="$output" \
    GITHUB_STEP_SUMMARY="$summary" \
    bash "$SCRIPT"
}

expect_exit() {
  local expected="$1"
  shift
  set +e
  "$@"
  local got=$?
  set -e
  if [ "$got" -ne "$expected" ]; then
    echo "expected exit $expected, got $got" >&2
    exit 1
  fi
}

expect_exit 64 env -u WAXEN_PATH WAXEN_INSTALL=false bash "$SCRIPT"

missing="$WORKDIR/missing.app"
expect_exit 66 env WAXEN_PATH="$missing" WAXEN_INSTALL=false bash "$SCRIPT"

expect_exit 1 run_action
grep -qx "diagnose" "$args_file"
grep -qx "$target" "$args_file"
grep -qx -- "--json" "$args_file"
grep -qx -- "--no-color" "$args_file"
grep -q "exit-code=1" "$output"
grep -q "launch-status=blocked" "$output"
grep -q "report-path=$report" "$output"
grep -q "verdict=tampered" "$output"
grep -q "Verdict:" "$summary"
python3 -c "import json,sys; assert json.load(open(sys.argv[1]))['launchStatus']=='blocked'" "$report"

WAXEN_FAIL_ON_BLOCKER=false expect_exit 0 run_action
grep -q "exit-code=1" "$output"
grep -q "launch-status=blocked" "$output"

WAXEN_FAKE_STATUS=0 WAXEN_FAKE_JSON='{"launchStatus":"clean"}' expect_exit 0 run_action
grep -q "exit-code=0" "$output"
grep -q "launch-status=clean" "$output"

WAXEN_FAKE_STATUS=0 WAXEN_FAKE_VERDICT=trusted WAXEN_FAKE_JSON='{"launchStatus":"clean"}' expect_exit 0 run_action
grep -q "verdict=trusted" "$output"

WAXEN_JSON=false expect_exit 1 run_action
grep -qx -- "--details" "$args_file"

WAXEN_FAKE_STATUS=66 expect_exit 66 run_action
WAXEN_FAKE_STATUS=66 WAXEN_FAIL_ON_ERROR=false expect_exit 0 run_action

echo "action wrapper assertions passed"

#!/bin/bash
# GitHub Action entry for waxen. Calls the real waxen CLI.
# It does not diagnose on its own and does not modify the target.
set -eu

path="${WAXEN_PATH:-}"
bin="${WAXEN_BIN:-}"
json="${WAXEN_JSON:-true}"
report_path="${WAXEN_REPORT_PATH:-waxen-report.json}"
fail_on_blocker="${WAXEN_FAIL_ON_BLOCKER:-true}"
fail_on_error="${WAXEN_FAIL_ON_ERROR:-true}"
allow_install="${WAXEN_INSTALL:-true}"

write_output() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$key" "$value" >>"$GITHUB_OUTPUT"
  fi
}

if [ -z "$path" ]; then
  echo "waxen: input 'path' is required" >&2
  write_output "exit-code" "64"
  write_output "launch-status" ""
  write_output "report-path" ""
  exit 64
fi

if [ ! -e "$path" ]; then
  echo "waxen: target does not exist: $path" >&2
  write_output "exit-code" "66"
  write_output "launch-status" ""
  write_output "report-path" ""
  exit 66
fi

if [ -z "$bin" ] && command -v waxen >/dev/null 2>&1; then
  bin="$(command -v waxen)"
fi

if [ -z "$bin" ]; then
  if [ "$allow_install" != "true" ]; then
    echo "waxen: waxen is not installed and install is disabled" >&2
    write_output "exit-code" "69"
    write_output "launch-status" ""
    write_output "report-path" ""
    exit 69
  fi
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "waxen: diagnosis requires a macOS runner" >&2
    write_output "exit-code" "78"
    write_output "launch-status" ""
    write_output "report-path" ""
    exit 78
  fi
  root="$(cd "$(dirname "$0")/.." && pwd)"
  swift build -c release --package-path "$root"
  bin="$root/.build/release/waxen"
fi

if [ ! -x "$bin" ]; then
  echo "waxen: waxen is not executable: $bin" >&2
  write_output "exit-code" "69"
  write_output "launch-status" ""
  write_output "report-path" ""
  exit 69
fi

mkdir -p "$(dirname "$report_path")"

# The plain-language verdict goes to the job summary and the `verdict` output.
set +e
share="$("$bin" diagnose "$path" --share --no-color 2>/dev/null)"
set -e
verdict="$(printf '%s\n' "$share" | sed -n 's/^- \*\*Verdict:\*\* `\([a-z]*\)`.*/\1/p' | head -n 1)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -n "$verdict" ]; then
  printf '%s\n' "$share" >>"$GITHUB_STEP_SUMMARY"
fi

set +e
if [ "$json" = "true" ]; then
  "$bin" diagnose "$path" --json --no-color >"$report_path"
  status=$?
else
  "$bin" diagnose "$path" --details --no-color >"$report_path"
  status=$?
fi
set -e

launch_status=""
if [ "$json" = "true" ] && [ -s "$report_path" ] && command -v python3 >/dev/null 2>&1; then
  launch_status="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("launchStatus") or "")
except Exception:
    print("")
' "$report_path")"
fi

write_output "exit-code" "$status"
write_output "launch-status" "$launch_status"
write_output "verdict" "$verdict"
write_output "report-path" "$report_path"

echo "waxen: exit $status launch-status=${launch_status:-unknown} verdict=${verdict:-unknown} report=$report_path"

if [ "$status" -eq 0 ]; then
  exit 0
fi

if [ "$status" -eq 1 ]; then
  if [ "$fail_on_blocker" = "true" ]; then
    echo "waxen: confirmed launch blocker" >&2
    exit 1
  fi
  echo "waxen: blocker recorded; fail-on-blocker is false"
  exit 0
fi

if [ "$fail_on_error" = "true" ]; then
  echo "waxen: waxen failed with exit $status" >&2
  exit "$status"
fi

echo "waxen: non-blocker failure recorded; fail-on-error is false"
exit 0

#!/bin/sh
# CLI skeleton: usage, unknown command, idle status.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

CS=./callscribe
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export CALLSCRIBE_STATE_DIR="$tmp/state"
export XDG_CONFIG_HOME="$tmp/config"

run "$CS"
assert_exit 1 "no arguments exits 1"
assert_contains "usage:" "no arguments prints usage"

run "$CS" bogus
assert_exit 1 "unknown command exits 1"

run "$CS" status
assert_exit 0 "status exits 0 when idle"
assert_eq idle "$OUT" "status prints idle"

finish

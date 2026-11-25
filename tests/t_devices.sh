#!/bin/sh
# devices and env subcommands.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

CS=./callscribe
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export CALLSCRIBE_STATE_DIR="$tmp/state"
export XDG_CONFIG_HOME="$tmp/config"
PATH="$PWD/tests/stubs:$PATH"
export PATH

run "$CS" devices
assert_exit 0 "devices exits 0"
assert_contains "source	fake.mic	Fake Microphone	selected" "default mic is selected"
assert_contains "source	other.mic	Other Microphone" "other source listed with description"
assert_contains "sink	fake.sink	Fake Output	selected" "default sink is selected"
assert_contains "sink	other.sink	Other Output" "other sink listed with description"

run env CALLSCRIBE_MIC_DEV=other.mic "$CS" devices
assert_contains "source	other.mic	Other Microphone	selected" "override moves the selected flag"
case "$OUT" in
*"source	fake.mic	Fake Microphone	selected"*) fail "default still flagged selected under override" ;;
*) printf 'ok: default no longer selected under override\n' ;;
esac

run env CALLSCRIBE_MIC_DEV=gone.mic "$CS" devices
assert_exit 0 "devices exits 0 with a missing override"
assert_contains "source	gone.mic	(missing)	selected,missing" "missing override flagged"

run env CALLSCRIBE_OUT_DIR=/nowhere/special CALLSCRIBE_MIC_DEV=m1 "$CS" env
assert_exit 0 "env exits 0"
assert_contains "CALLSCRIBE_OUT_DIR=/nowhere/special" "env reflects OUT_DIR"
assert_contains "CALLSCRIBE_MIC_DEV=m1" "env reflects MIC_DEV"
assert_contains "CALLSCRIBE_STATE_DIR=$CALLSCRIBE_STATE_DIR" "env reflects effective state dir"
assert_contains "CALLSCRIBE_MODEL=" "env lists the model"

finish

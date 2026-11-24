#!/bin/sh
# Capture lifecycle: start, refuse double start, status, stop, dead-recorder stop.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

CS=./callscribe
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export CALLSCRIBE_STATE_DIR="$tmp/state"
export XDG_CONFIG_HOME="$tmp/config"
export STUB_LOG="$tmp/stub.log"
PATH="$PWD/tests/stubs:$PATH"
export PATH

run "$CS" start
assert_exit 0 "start exits 0"
assert_contains "fake.mic" "start prints the mic device"
assert_contains "fake.sink.monitor" "start prints the monitor target"

session=$(cat "$CALLSCRIBE_STATE_DIR/current" 2>/dev/null)
dir="$CALLSCRIBE_STATE_DIR/sessions/$session"
if [ -n "$session" ] && [ -f "$dir/meta" ]; then
	printf 'ok: session dir and meta exist\n'
else
	fail "session dir or meta missing"
fi
grep -q '^MIC_DEV=fake.mic$' "$dir/meta" 2>/dev/null && printf 'ok: meta has mic device\n' || fail "meta lacks MIC_DEV"
grep -q '^SYS_DEV=fake.sink$' "$dir/meta" 2>/dev/null && printf 'ok: meta has sink device\n' || fail "meta lacks SYS_DEV"

MIC_PID='' SYS_PID=''
[ -f "$dir/pids" ] && . "$dir/pids"
kill -0 "$MIC_PID" 2>/dev/null && printf 'ok: mic recorder running\n' || fail "mic recorder not running"
kill -0 "$SYS_PID" 2>/dev/null && printf 'ok: system recorder running\n' || fail "system recorder not running"

run "$CS" start
assert_exit 1 "second start is refused"

run "$CS" status
assert_exit 0 "status exits 0 while recording"
assert_contains "recording $session" "status names the session"

run "$CS" stop
assert_exit 0 "stop exits 0"
[ ! -f "$CALLSCRIBE_STATE_DIR/current" ] && printf 'ok: current removed\n' || fail "current still present"
grep -q '^ENDED_EPOCH=' "$dir/meta" && printf 'ok: meta has ENDED_EPOCH\n' || fail "meta lacks ENDED_EPOCH"
kill -0 "$MIC_PID" 2>/dev/null && fail "mic recorder survived stop" || printf 'ok: mic recorder gone\n'
kill -0 "$SYS_PID" 2>/dev/null && fail "system recorder survived stop" || printf 'ok: system recorder gone\n'
assert_contains "$dir" "stop invoked process_session with the session dir"

run "$CS" stop
assert_exit 1 "stop with no session exits 1"

# A recorder dying mid-call must not break stop.
sleep 1
run "$CS" start
assert_exit 0 "start again exits 0"
session2=$(cat "$CALLSCRIBE_STATE_DIR/current")
dir2="$CALLSCRIBE_STATE_DIR/sessions/$session2"
MIC_PID='' SYS_PID=''
. "$dir2/pids"
kill -TERM "$SYS_PID" 2>/dev/null
while kill -0 "$SYS_PID" 2>/dev/null; do sleep 0.1; done
run "$CS" stop
assert_exit 0 "stop after a dead recorder exits 0"
assert_contains "system recorder" "stop warns about the dead system recorder"
[ ! -f "$CALLSCRIBE_STATE_DIR/current" ] && printf 'ok: current removed after degraded stop\n' || fail "current still present after degraded stop"

finish

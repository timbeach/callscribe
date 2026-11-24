#!/bin/sh
# Capture lifecycle: start, refuse double start, status, stop, dead-recorder stop.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

CS=./callscribe
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export CALLSCRIBE_STATE_DIR="$tmp/state"
export XDG_CONFIG_HOME="$tmp/config"
export CALLSCRIBE_OUT_DIR="$tmp/out"
export CALLSCRIBE_MODEL="$tmp/model.bin"
export STUB_LOG="$tmp/stub.log"
: >"$CALLSCRIBE_MODEL"
PATH="$PWD/tests/stubs:$PATH"
export PATH

run "$CS" start
assert_exit 0 "start exits 0"
assert_contains "fake.mic" "start prints the mic device"
assert_contains "fake.sink (monitor)" "start prints the monitor target"
grep -q 'pw-record .*stream\.capture\.sink=true.*--target fake\.sink .*sys\.wav' "$STUB_LOG" &&
	printf 'ok: sys capture targets the sink with stream.capture.sink\n' ||
	fail "sys pw-record not invoked with stream.capture.sink=true against the sink"
grep -q 'pw-record .*node\.dont-fallback=true.*--target fake\.mic .*mic\.wav' "$STUB_LOG" &&
	printf 'ok: mic capture refuses fallback targets\n' ||
	fail "mic pw-record not invoked with node.dont-fallback=true"
grep -q 'pw-record .*fake\.sink\.monitor' "$STUB_LOG" &&
	fail "sys pw-record still targets the fake pulse .monitor name" ||
	printf 'ok: no .monitor pseudo-target used\n'

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
assert_contains -call.md "stop ran processing and reported a transcript path"
grep -q '^notify-send ' "$STUB_LOG" && printf 'ok: stop sent a desktop notification\n' || fail "stop sent no desktop notification"

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
assert_contains -call "degraded stop still reports a transcript path"
[ ! -f "$CALLSCRIBE_STATE_DIR/current" ] && printf 'ok: current removed after degraded stop\n' || fail "current still present after degraded stop"

# A recorder that dies at launch must not report success.
sleep 1
run env STUB_PWRECORD_FAIL=1 "$CS" start
assert_exit 1 "start fails when a recorder dies at launch"
[ ! -f "$CALLSCRIBE_STATE_DIR/current" ] && printf 'ok: no current after failed launch\n' || fail "failed launch left a current file"

# Stale state: a reused PID that is not a recorder must not be signalled.
sleep 60 &
bystander=$!
fake=99990101-000000
fdir="$CALLSCRIBE_STATE_DIR/sessions/$fake"
mkdir -p "$fdir"
printf 'SESSION=%s\nSTARTED_EPOCH=%s\nMIC_DEV=fake.mic\nSYS_DEV=fake.sink\n' "$fake" "$(date +%s)" >"$fdir/meta"
printf 'MIC_PID=%s\nSYS_PID=\n' "$bystander" >"$fdir/pids"
printf '%s\n' "$fake" >"$CALLSCRIBE_STATE_DIR/current"
run "$CS" stop
assert_exit 0 "stop survives stale pids"
if kill -0 "$bystander" 2>/dev/null; then
	printf 'ok: bystander process not killed\n'
else
	fail "stop killed an unrelated process via a stale pid"
fi
kill "$bystander" 2>/dev/null
assert_contains "mic recorder" "stop warns about the stale mic recorder"

# toggle: starts when idle, stops when recording.
sleep 1
run "$CS" toggle
assert_exit 0 "toggle starts when idle"
[ -f "$CALLSCRIBE_STATE_DIR/current" ] && printf 'ok: toggle started a session\n' || fail "toggle did not start a session"
run "$CS" toggle
assert_exit 0 "toggle stops when recording"
[ ! -f "$CALLSCRIBE_STATE_DIR/current" ] && printf 'ok: toggle stopped the session\n' || fail "toggle did not stop the session"

finish

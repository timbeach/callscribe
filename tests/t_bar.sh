#!/bin/sh
# sb-callscribe: status output and BLOCK_BUTTON click handling.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export STUB_LOG="$tmp/stub.log"
mkdir -p "$tmp/bin"

cat >"$tmp/bin/callscribe" <<'EOF'
#!/bin/sh
printf 'callscribe %s\n' "$*" >>"$STUB_LOG"
case "$1" in
status) printf '%s\n' "${FAKE_STATUS:-idle}" ;;
toggle) sleep 3 ;;
esac
EOF
cat >"$tmp/bin/callscribe-gui" <<'EOF'
#!/bin/sh
printf 'callscribe-gui\n' >>"$STUB_LOG"
EOF
cat >"$tmp/bin/pkill" <<'EOF'
#!/bin/sh
printf 'pkill %s\n' "$*" >>"$STUB_LOG"
EOF
chmod 755 "$tmp/bin/callscribe" "$tmp/bin/callscribe-gui" "$tmp/bin/pkill"
PATH="$tmp/bin:$PATH"
export PATH

SB=./sb-callscribe

run "$SB"
assert_exit 0 "idle run exits 0"
case "$OUT" in
*🔴*) fail "idle output shows the recording marker" ;;
*) printf 'ok: no recording marker when idle\n' ;;
esac

run env FAKE_STATUS="recording x 754s" "$SB"
assert_exit 0 "recording run exits 0"
assert_contains "🔴" "recording shows the red marker"
assert_contains "12:34" "recording shows mm:ss elapsed"

: >"$STUB_LOG"
run env BLOCK_BUTTON=1 "$SB"
assert_exit 0 "button 1 exits 0"
sleep 1
n=$(grep -c '^callscribe-gui$' "$STUB_LOG")
assert_eq 1 "$n" "button 1 spawns the gui exactly once"

: >"$STUB_LOG"
run timeout 1 env BLOCK_BUTTON=3 "$SB"
assert_exit 0 "button 3 returns within a second despite a slow stop"
sleep 3.5
grep -q '^callscribe toggle$' "$STUB_LOG" && printf 'ok: button 3 ran toggle\n' || fail "button 3 did not run toggle"
grep -q '^pkill -RTMIN+12 dwmblocks$' "$STUB_LOG" && printf 'ok: button 3 refreshed the bar\n' || fail "button 3 did not signal dwmblocks"

finish

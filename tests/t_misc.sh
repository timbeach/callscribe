#!/bin/sh
# clean, summarize, and the setup no-op path.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

CS=./callscribe
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export CALLSCRIBE_STATE_DIR="$tmp/state"
export XDG_CONFIG_HOME="$tmp/config"
export CALLSCRIBE_MODEL="$tmp/model.bin"
export STUB_LOG="$tmp/stub.log"
: >"$CALLSCRIBE_MODEL"
PATH="$PWD/tests/stubs:$PATH"
export PATH

# clean: finished session loses WAVs, keeps meta and JSON; active session untouched.
fin="$CALLSCRIBE_STATE_DIR/sessions/20260101-100000"
act="$CALLSCRIBE_STATE_DIR/sessions/20260101-110000"
mkdir -p "$fin" "$act"
printf 'audio-bytes' >"$fin/mic.wav"
printf 'audio-bytes' >"$fin/sys.wav"
printf 'SESSION=x\n' >"$fin/meta"
printf '{}' >"$fin/mic.json"
printf 'audio-bytes' >"$act/mic.wav"
printf '20260101-110000\n' >"$CALLSCRIBE_STATE_DIR/current"

run "$CS" clean
assert_exit 0 "clean exits 0"
assert_contains "reclaimed" "clean reports reclaimed space"
[ ! -f "$fin/mic.wav" ] && [ ! -f "$fin/sys.wav" ] && printf 'ok: finished session WAVs removed\n' || fail "finished WAVs survived clean"
[ -f "$fin/meta" ] && [ -f "$fin/mic.json" ] && printf 'ok: meta and JSON kept\n' || fail "clean deleted non-WAV files"
[ -f "$act/mic.wav" ] && printf 'ok: active session untouched\n' || fail "clean touched the active session"
rm -f "$CALLSCRIBE_STATE_DIR/current"

# summarize
note="$tmp/note.md"
printf '# a call\nhello\n' >"$note"

run env CALLSCRIBE_CLAUDE_BIN=absent-claude-bin "$CS" summarize "$note"
assert_exit 1 "summarize without claude exits 1"
assert_contains "CALLSCRIBE_CLAUDE_BIN" "summarize names the config variable"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/fake-claude" <<'EOF'
#!/bin/sh
cat >/dev/null
echo canned summary
EOF
chmod 755 "$tmp/bin/fake-claude"
run env CALLSCRIBE_CLAUDE_BIN="$tmp/bin/fake-claude" "$CS" summarize "$note"
assert_exit 0 "summarize with stub claude exits 0"
assert_contains "canned summary" "summarize prints the model output"

run "$CS" summarize "$tmp/absent.md"
assert_exit 1 "summarize on a missing file exits 1"

# setup: everything present means no network and a clear no-op message.
: >"$STUB_LOG"
run "$CS" setup
assert_exit 0 "setup exits 0 when nothing is needed"
assert_contains "nothing to do" "setup says nothing is needed"
if grep -qE '^(git|curl) ' "$STUB_LOG"; then
	fail "setup touched the network when nothing was needed"
else
	printf 'ok: setup made no git or curl calls\n'
fi

finish

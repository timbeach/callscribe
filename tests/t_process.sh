#!/bin/sh
# Processing pipeline: resample, silence warning, whisper, Markdown output.
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

# A finished session: 2s of tone on mic, 2s of silence on sys.
s1=20260101-120000
d1="$CALLSCRIBE_STATE_DIR/sessions/$s1"
mkdir -p "$d1"
ffmpeg -nostdin -loglevel error -f lavfi -i "sine=frequency=440:duration=2" -ar 48000 -ac 2 "$d1/mic.wav" || exit 1
ffmpeg -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 2 "$d1/sys.wav" || exit 1
cat >"$d1/meta" <<EOF
SESSION=$s1
STARTED_EPOCH=1767268800
MIC_DEV=fake.mic
SYS_DEV=fake.sink
ENDED_EPOCH=1767268920
EOF

run "$CS" transcribe "$s1"
assert_exit 0 "transcribe exits 0"
assert_contains "sys stream is silent" "warns that the sys stream is silent"

md=$(find "$CALLSCRIBE_OUT_DIR" -name '*-call.md' | head -1)
if [ -n "$md" ]; then
	printf 'ok: Markdown transcript written\n'
else
	fail "no Markdown transcript in CALLSCRIBE_OUT_DIR"
	finish
fi
grep -q '^mic_device: fake.mic$' "$md" && printf 'ok: frontmatter mic device\n' || fail "frontmatter lacks mic_device"
grep -q '^sys_device: fake.sink$' "$md" && printf 'ok: frontmatter sys device\n' || fail "frontmatter lacks sys_device"
grep -q '^duration_seconds: 120$' "$md" && printf 'ok: frontmatter duration\n' || fail "frontmatter lacks duration"
grep -q '\*\*\[0:00:01\] You:\*\* canned you line' "$md" && printf 'ok: body has You line\n' || fail "body lacks You line"

run env CALLSCRIBE_WHISPER_BIN=definitely-absent-whisper "$CS" transcribe "$s1"
assert_exit 1 "missing whisper binary exits 1"
assert_contains "CALLSCRIBE_WHISPER_BIN" "missing binary names the config variable"

run env CALLSCRIBE_MODEL="$tmp/absent-model.bin" "$CS" transcribe "$s1"
assert_exit 1 "missing model exits 1"
assert_contains "CALLSCRIBE_MODEL" "missing model names the config variable"

run "$CS" transcribe no-such-session
assert_exit 1 "unknown session exits 1"

# A session whose sys.wav never got written still produces a one-sided transcript.
s2=20260101-130000
d2="$CALLSCRIBE_STATE_DIR/sessions/$s2"
mkdir -p "$d2"
cp "$d1/mic.wav" "$d2/mic.wav"
sed "s/$s1/$s2/; s/1767268800/1767272400/; s/1767268920/1767272520/" "$d1/meta" >"$d2/meta"
run "$CS" transcribe "$s2"
assert_exit 0 "one-sided session transcribes"
assert_contains "sys stream has no audio" "warns about the missing sys stream"
md2=$(find "$CALLSCRIBE_OUT_DIR" -name '*-call.md' | grep -v "$(basename "$md")" | head -1)
[ -n "$md2" ] && grep -q 'canned you line' "$md2" && printf 'ok: one-sided transcript has You line\n' || fail "one-sided transcript missing You line"
grep -q 'canned them line' "$md2" && fail "one-sided transcript has phantom Them line" || printf 'ok: no phantom Them line\n'

finish

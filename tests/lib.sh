# Shared helpers for callscribe test scripts. POSIX sh, sourced not run.

fails=0

# run CMD...: execute, capturing combined output in OUT and exit code in STATUS.
run() {
	OUT=$("$@" 2>&1)
	STATUS=$?
}

fail() {
	printf 'FAIL: %s\n' "$*"
	fails=$((fails + 1))
}

# assert_eq EXPECTED ACTUAL LABEL
assert_eq() {
	if [ "$1" = "$2" ]; then
		printf 'ok: %s\n' "$3"
	else
		fail "$3 (expected '$1', got '$2')"
	fi
}

# assert_exit CODE LABEL: checks STATUS from the last run().
assert_exit() {
	if [ "$STATUS" -eq "$1" ]; then
		printf 'ok: %s\n' "$2"
	else
		fail "$2 (expected exit $1, got $STATUS)"
	fi
}

# assert_contains NEEDLE LABEL: checks OUT from the last run().
assert_contains() {
	case "$OUT" in
	*"$1"*) printf 'ok: %s\n' "$2" ;;
	*) fail "$2 (output did not contain '$1'; got: $OUT)" ;;
	esac
}

finish() {
	if [ "$fails" -eq 0 ]; then
		exit 0
	fi
	printf '%d assertion(s) failed\n' "$fails"
	exit 1
}

# callscribe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A suckless-style CLI that records both sides of any call on a PipeWire Linux box as two streams, transcribes them locally with whisper.cpp, and writes one timestamped You/Them Markdown transcript.

**Architecture:** One POSIX sh entry script (`callscribe`) dispatches subcommands, manages pw-record capture sessions under XDG state, and orchestrates an ffmpeg resample, two whisper-cli runs, and a stdlib-Python merge script that interleaves the two JSON transcripts by timestamp into Markdown.

**Tech Stack:** POSIX sh, pw-record (PipeWire), pactl, ffmpeg, whisper.cpp (`whisper-cli`), Python 3 stdlib (merge + its tests), plain sh test scripts, make.

**Spec:** `docs/superpowers/specs/2026-11-24-callscribe-design.md`

## Global Constraints

- Repo root: `~/code/callscribe`. MIT license. Shareable later via the aegixlinux org and AUR.
- `callscribe` and all sh test scripts are POSIX sh with `#!/bin/sh`; no bashisms. The merge script is Python 3 stdlib only.
- No em dashes or en dashes in any file, comment, commit message, or doc. Use commas, colons, parentheses, or periods.
- Nothing machine-specific hardcoded: devices come from `pactl get-default-source` / `get-default-sink` at start time. The string "Volt" must not appear in code.
- No network access at runtime, except `callscribe setup` (model download, with confirmation) and `callscribe summarize` (pipes to the `claude` CLI, optional, never automatic).
- Manual start only. No daemon, no auto-record.
- Config file `${XDG_CONFIG_HOME:-$HOME/.config}/callscribe/config` is optional, sourced as sh. Variables and defaults: `CALLSCRIBE_OUT_DIR=$HOME/Documents/PERSONAL/meetings`, `CALLSCRIBE_MODEL=$HOME/.local/share/callscribe/models/ggml-small.bin`, `CALLSCRIBE_WHISPER_BIN=whisper-cli`, `CALLSCRIBE_LANG=en`, `CALLSCRIBE_SILENCE_DB=-50`.
- State: `${XDG_STATE_HOME:-$HOME/.local/state}/callscribe/`, sessions at `sessions/<YYYYMMDD-HHMMSS>/` containing `mic.wav`, `sys.wav`, `meta`, `pids`. `current` is a text file naming the active session id; its absence means idle.
- All tests must pass with no audio hardware and no whisper.cpp installed (external binaries are stubbed via PATH in tests). `make test` runs everything.
- Commit messages end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## Review Focus

Spec-implied failure modes, each pinned to a test in the task that owns it:

1. `stop` with no active session must print an error and exit 1, not crash or process garbage. (Task 3)
2. `start` while already recording must refuse and exit 1, leaving the running session untouched. (Task 3)
3. One pw-record dying mid-call (suspend, device unplug) must not lose the other stream: `stop` processes whatever audio exists and says what it could not do. (Task 3)
4. A silent stream (wrong sink recorded, muted mic) must produce a loud warning naming the stream, while still writing the transcript of the non-silent one. (Task 4)
5. Missing `whisper-cli` or missing model file must fail before any processing with a message naming the binary or path and the config variable that fixes it. (Task 4)

---

### Task 1: Repo scaffold and CLI skeleton

**Files:**
- Create: `callscribe` (mode 755), `LICENSE`, `README.md`, `Makefile`, `tests/lib.sh`, `tests/t_cli.sh`, `.gitignore`

**Interfaces:**
- Produces: `callscribe <command>` dispatch; unknown or missing command prints usage to stderr, exit 1. `callscribe status` prints `idle` (exit 0) when no `current` file exists. Internal helpers later tasks use: `die <msg>` (stderr + exit 1), `load_config` (sets the `CALLSCRIBE_*` defaults then sources the config file if present), `state_dir` (echoes the state root, honoring `CALLSCRIBE_STATE_DIR` override so tests can redirect it).
- Produces: `tests/lib.sh` with `assert_eq <expected> <actual> <label>` and `assert_exit <code> <label>`; `make test` runs every `tests/t_*.sh` with sh and fails if any fails.

- [ ] **Step 1: `git init`, write `LICENSE` (MIT, holder "Timothy Beach"), `.gitignore` (`*.wav`, `models/`), and a README stub (one-paragraph description, headset requirement, consent note per spec)**
- [ ] **Step 2: Write `tests/t_cli.sh` asserting: no args exits 1 and prints a line starting `usage:`; `callscribe bogus` exits 1; `callscribe status` with `CALLSCRIBE_STATE_DIR` pointed at an empty temp dir prints `idle` and exits 0**
- [ ] **Step 3: Run `sh tests/t_cli.sh`; expected: FAIL (callscribe not found or no output)**
- [ ] **Step 4: Implement `callscribe` dispatch with `die`, `load_config`, `state_dir`, and the `status` command; write the `Makefile` (`test`, `install` to `$(PREFIX)/bin` default `~/.local/bin`, `uninstall`)**
- [ ] **Step 5: Run `make test`; expected: PASS**
- [ ] **Step 6: Commit `feat: callscribe CLI skeleton with config and state helpers`**

### Task 2: Merge script

**Files:**
- Create: `callscribe-merge` (mode 755, Python 3 stdlib), `tests/test_merge.py`

**Interfaces:**
- Produces: `callscribe-merge YOU.json THEM.json` reads two whisper.cpp `-oj` JSON files (segments under `transcription`, each with `offsets.from`/`offsets.to` in ms and `text`), prints to stdout one line per segment, sorted by `offsets.from` ascending (ties: You first): `**[H:MM:SS] You:** text` or `**[H:MM:SS] Them:** text`. Empty or missing `transcription` key in one file is fine (the other still prints). Whitespace-only segments are dropped. Exit 1 with a stderr message if a file is unreadable or not JSON.

- [ ] **Step 1: Write `tests/test_merge.py` (unittest) with fixtures as dicts written to temp files: interleaving across both files sorts by offset; tie goes to You; empty `transcription` in one file; whitespace segment dropped; malformed JSON exits 1. Assert on captured stdout of `subprocess.run`**
- [ ] **Step 2: Run `python3 -m unittest tests/test_merge.py -v`; expected: FAIL (script missing)**
- [ ] **Step 3: Implement `callscribe-merge`**
- [ ] **Step 4: Run the tests; expected: PASS. Add `python3 -m unittest discover -s tests` to `make test`**
- [ ] **Step 5: Commit `feat: timestamp merge of You/Them whisper transcripts`**

### Task 3: Capture start and stop

**Files:**
- Modify: `callscribe`
- Create: `tests/t_capture.sh`, `tests/stubs/pw-record`, `tests/stubs/pactl`

**Interfaces:**
- Consumes: `die`, `load_config`, `state_dir` from Task 1.
- Produces: `callscribe start`: refuses (exit 1) if `current` exists; captures default source and sink names via `pactl get-default-source|get-default-sink`; creates the session dir; writes `meta` (sh-sourcable: `SESSION=`, `STARTED_EPOCH=`, `MIC_DEV=`, `SYS_DEV=`); launches `pw-record --target "$MIC_DEV" mic.wav` and `pw-record --target "$SYS_DEV.monitor" sys.wav` in the background; writes both PIDs to `pids`; writes `current`; prints both device names. `callscribe stop`: exit 1 with message if no `current`; SIGTERMs the PIDs that are still alive, waits for exit; appends `ENDED_EPOCH=` to `meta`; removes `current`; warns per stream if its recorder had already died or its WAV is missing; then invokes `process_session <dir>` (Task 4; until then a stub function that echoes the dir). `callscribe status` now prints `recording <session> <elapsed>s` when active.

- [ ] **Step 1: Write stub `pw-record` (touches its last argument, sleeps until SIGTERM) and stub `pactl` (echoes fixed fake device names), both honoring a log file env var so tests can assert invocations**
- [ ] **Step 2: Write `tests/t_capture.sh` running `callscribe` with `PATH=tests/stubs:$PATH` and a temp state dir: start creates session with meta naming the fake devices and two live PIDs; second start exits 1; status shows recording; stop removes `current`, appends ENDED_EPOCH, and both stub processes are gone; stop again exits 1; killing one stub before stop still stops cleanly with a warning mentioning that stream (Review Focus 1, 2, 3)**
- [ ] **Step 3: Run it; expected: FAIL**
- [ ] **Step 4: Implement `start`, `stop`, `status` elapsed, and the `process_session` stub in `callscribe`**
- [ ] **Step 5: Run `make test`; expected: PASS**
- [ ] **Step 6: Commit `feat: two-stream capture sessions with routing printout`**

### Task 4: Processing pipeline (resample, silence check, whisper, Markdown)

**Files:**
- Modify: `callscribe`
- Create: `tests/t_process.sh`, `tests/stubs/whisper-cli`

**Interfaces:**
- Consumes: session layout from Task 3; `callscribe-merge` from Task 2.
- Produces: `process_session <dir>` for real: checks `$CALLSCRIBE_WHISPER_BIN` exists on PATH and `$CALLSCRIBE_MODEL` file exists, else `die` naming the missing thing and its config variable (Review Focus 5); per existing WAV, resamples to 16 kHz mono (`ffmpeg -i in.wav -ar 16000 -ac 1`), measures mean volume with `ffmpeg -af volumedetect` and warns `WARNING: <stream> stream is silent` when below `$CALLSCRIBE_SILENCE_DB` (Review Focus 4); runs `$CALLSCRIBE_WHISPER_BIN -m "$CALLSCRIBE_MODEL" -l "$CALLSCRIBE_LANG" -f <16k.wav> -oj -of <base>`; merges the JSONs with `callscribe-merge` (an absent stream contributes an empty transcript); writes `$CALLSCRIBE_OUT_DIR/<YYYY-MM-DD-HHMM>-call.md` (creating the dir) with YAML frontmatter (`date`, `start`, `duration_seconds`, `mic_device`, `sys_device`) and the merged body; prints the output path. Also wires `callscribe transcribe <session-id>` to rerun `process_session` on a finished session.

- [ ] **Step 1: Write stub `whisper-cli` that writes a canned `-oj` JSON (distinct text per input filename) to the `-of` path**
- [ ] **Step 2: Write `tests/t_process.sh`: build a fake finished session using ffmpeg-generated audio (`sine` tone mic.wav, `anullsrc` silent sys.wav, 2s each); run `callscribe transcribe` with stubbed whisper-cli and temp OUT_DIR; assert the Markdown file exists, frontmatter has the meta values, body contains the canned You text, stderr contains the silent-sys warning; assert missing whisper binary and missing model each exit 1 naming `CALLSCRIBE_WHISPER_BIN` / `CALLSCRIBE_MODEL`; assert a session whose sys.wav is absent still produces a transcript with a warning**
- [ ] **Step 3: Run it; expected: FAIL**
- [ ] **Step 4: Implement `process_session` and `transcribe` in `callscribe`**
- [ ] **Step 5: Run `make test`; expected: PASS**
- [ ] **Step 6: Commit `feat: local whisper pipeline from session to Markdown transcript`**

### Task 5: setup, clean, summarize

**Files:**
- Modify: `callscribe`, `README.md`
- Create: `tests/t_misc.sh`

**Interfaces:**
- Consumes: everything above.
- Produces: `callscribe setup`: builds whisper.cpp if `$CALLSCRIBE_WHISPER_BIN` is absent (clone `https://github.com/ggml-org/whisper.cpp` into `~/.local/src/whisper.cpp`, `make`, symlink the binary into `~/.local/bin`), then offers the model download (small by default, URL from the whisper.cpp models README) into `dirname $CALLSCRIBE_MODEL`; every network action prints what and where and asks `[y/N]` first. `callscribe clean`: deletes WAVs (not meta or JSON) from finished sessions, prints reclaimed size; active session untouched. `callscribe summarize <note.md>`: `die` if `claude` CLI absent; else pipes the note into `claude -p` with a fixed follow-up prompt and prints the result; never called by any other command.

- [ ] **Step 1: Write `tests/t_misc.sh`: `clean` on a fixture session dir removes WAVs, keeps `meta`, skips a session named in `current`; `summarize` with no `claude` on PATH exits 1; `setup` with everything already present prints that nothing is needed and makes no network call (assert with a stub `git`/`curl` log that stays empty)**
- [ ] **Step 2: Run it; expected: FAIL**
- [ ] **Step 3: Implement the three commands; expand README: dependencies, setup, usage, config reference, headset requirement, consent paragraph, Aegix notes**
- [ ] **Step 4: Run `make test`; expected: PASS**
- [ ] **Step 5: Commit `feat: setup, clean, and summarize commands`**

### Task 6: dwm and dwmblocks integration snippets

**Files:**
- Create: `contrib/dwm-keybind.diff.example`, `contrib/dwmblocks-callscribe.sh`

**Interfaces:**
- Consumes: `callscribe status` and `start`/`stop` from Task 3.
- Produces: `contrib/dwmblocks-callscribe.sh`: prints a red dot marker string when `callscribe status` reports recording, empty when idle (exit 0 both ways). `contrib/dwm-keybind.diff.example`: a documented config.h snippet binding a toggle: a tiny `callscribe toggle` command (add to `callscribe`: start if idle, stop if recording) so one key does both.

- [ ] **Step 1: Add a `toggle` assertion to `tests/t_capture.sh` (idle toggle starts; recording toggle stops)**
- [ ] **Step 2: Run it; expected: FAIL**
- [ ] **Step 3: Implement `toggle`, write both contrib files with install comments**
- [ ] **Step 4: Run `make test`; expected: PASS**
- [ ] **Step 5: Commit `feat: toggle command and dwm/dwmblocks contrib`**

### Task 7: Real-hardware verification and model benchmark (interactive, with Timothy)

**Files:**
- Modify: `README.md` (recorded benchmark numbers), config file on this machine (chosen model)

**Interfaces:**
- Consumes: the whole tool.

- [ ] **Step 1: Run `callscribe setup` for real (whisper.cpp build, small and medium model downloads, with Timothy's confirmation)**
- [ ] **Step 2: With Timothy on his headset, record a 2 to 3 minute test call (a YouTube video playing counts as Them), `callscribe start` then `stop`**
- [ ] **Step 3: Verify the Markdown: both speakers present, attribution correct, timestamps sane, no silence warnings**
- [ ] **Step 4: `callscribe transcribe` the same session with the medium model; record both models' processing time per audio minute in the README and set the better tradeoff as this machine's configured default**
- [ ] **Step 5: Commit `docs: benchmark results and default model choice`**

---

## Self-review notes

Spec coverage checked: capture, attribution, routing safety, silence check, output format, config, state, CLI surface, toggle/keybind/dwmblocks, setup, clean, summarize, consent documentation, headset requirement, portability constraints all have owning tasks; echo cancellation and mobile are spec non-goals. Interface names were cross-checked (`process_session`, `current`, meta keys, merge CLI). Review Focus items 1 to 5 each have a named test in Tasks 3 to 4.

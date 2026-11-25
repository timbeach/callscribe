# callscribe GUI and Aegix Bar Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A clickable dwmblocks block and a floating tkinter window giving callscribe a mouse-first start/validate/stop flow, with device pickers that persist to config and a secondary transcript list.

**Architecture:** The CLI stays the single source of truth: it grows device-override variables, a `devices` listing, an `env` dump, and session/model frontmatter. The GUI (`callscribe-gui`, one Python file) shells out to the CLI for every fact and action, keeping its own logic to parsing and rendering; all parsing lives in plain functions importable without Tk so tests run headless. The bar script `sb-callscribe` is a thin status printer with BLOCK_BUTTON click handling.

**Tech Stack:** POSIX sh (CLI, bar script, sh tests), Python 3 stdlib + tkinter (GUI), unittest, make.

**Spec:** `docs/superpowers/specs/2026-11-24-callscribe-gui-design.md` (mockup beside it: `2026-11-24-callscribe-gui-mockup.html`)

## Global Constraints

- Python stdlib only, no venv, no pip. If tkinter is missing, `callscribe-gui` exits 1 with a message naming the tk package.
- `sb-callscribe` and all sh tests are POSIX sh. All existing CLI conventions (config precedence, state layout, warn_to, stubs via PATH) carry over.
- All automated tests run headless: no X, no Tk root, no real pactl/pw-record/whisper (PATH stubs as in the existing tests). The Tk layer is verified live in the final task.
- No em or en dashes in any file, comment, or commit message.
- dwmblocks update signal 12. WM_CLASS instance/class "callscribe". Recompiling dwm/dwmblocks is the user's action; this repo ships snippets.
- The GUI never downloads models and writes config only for device changes.
- No Co-Authored-By trailers (user hook bans them).

## Review Focus

1. The GUI rewriting config must never clobber unrelated lines or comments the user put there. (Task 4)
2. Pre-GUI transcripts lacking `session:`/`model:` frontmatter must list cleanly with re-run disabled, not crash or guess. (Task 4)
3. A configured device that is absent at `start` must die naming the device and its variable; `devices` must flag it so the GUI can block START. (Tasks 1 and 2)
4. Unexpected `callscribe status` output (stale state, corrupt meta) must render as idle-with-warning in the GUI, never a crash. (Task 4)
5. An empty or missing CALLSCRIBE_OUT_DIR must produce an empty transcript list, not an exception. (Task 4)

---

### Task 1: CLI device overrides

**Files:**
- Modify: `callscribe` (load_config, cmd_start), `tests/t_capture.sh`, `tests/stubs/pactl`

**Interfaces:**
- Produces: config vars `CALLSCRIBE_MIC_DEV` and `CALLSCRIBE_SYS_DEV` (default empty) in load_config's preserve list and defaults. In `cmd_start`: when non-empty, the override is used instead of the pactl default; before recording, each chosen device (override or default) is checked against `pactl list short sources` / `list short sinks` and a missing override dies `configured mic device '<name>' not found; fix CALLSCRIBE_MIC_DEV or the GUI picker` (same shape for SYS).
- Produces: stub `pactl` additionally answers `list short sources` with lines for `fake.mic` and `other.mic`, and `list short sinks` with `fake.sink` and `other.sink` (tab-separated short format).

- [ ] **Step 1: Extend stub pactl; add to t_capture.sh:** start with `CALLSCRIBE_MIC_DEV=other.mic` logs `--target other.mic`; start with `CALLSCRIBE_MIC_DEV=gone.mic` exits 1, output contains `gone.mic` and `CALLSCRIBE_MIC_DEV`, and no `current` file remains; same two cases for `CALLSCRIBE_SYS_DEV` (Review Focus 3)
- [ ] **Step 2: Run t_capture.sh; expected: FAIL on the new assertions**
- [ ] **Step 3: Implement in `callscribe`**
- [ ] **Step 4: Run `make test`; expected: PASS**
- [ ] **Step 5: Commit `feat: device override config for capture targets`**

### Task 2: devices and env subcommands

**Files:**
- Modify: `callscribe`, `tests/stubs/pactl`
- Create: `tests/t_devices.sh`

**Interfaces:**
- Produces: `callscribe devices`: one line per device, `kind<TAB>node-name<TAB>description<TAB>flags`, kind `source` or `sink`, flags a comma list from: `selected` (the device start would use right now), `missing` (a configured override not present; its line carries the override name and description `(missing)`). Descriptions come from `pactl list sources` / `list sinks` blocks (`Name:` / `Description:` fields).
- Produces: `callscribe env`: every effective config value after load_config, one `CALLSCRIBE_<NAME>=<value>` line per variable, covering OUT_DIR MODEL WHISPER_BIN WHISPER_FLAGS LANG SILENCE_DB CLAUDE_BIN STATE_DIR MIC_DEV SYS_DEV.
- Produces: stub `pactl` answers `list sources` / `list sinks` with two canned blocks each (Name/Description pairs matching the short lists).

- [ ] **Step 1: Write `tests/t_devices.sh`:** devices lists both sources and both sinks with descriptions; default run flags `fake.mic` and `fake.sink` as `selected`; with `CALLSCRIBE_MIC_DEV=other.mic` the `selected` flag moves; with `CALLSCRIBE_MIC_DEV=gone.mic` a `source	gone.mic	(missing)	selected,missing` line appears; `env` output contains `CALLSCRIBE_OUT_DIR=` and `CALLSCRIBE_MIC_DEV=` lines reflecting the environment
- [ ] **Step 2: Run it; expected: FAIL**
- [ ] **Step 3: Implement both subcommands and usage lines in `callscribe`**
- [ ] **Step 4: Run `make test`; expected: PASS**
- [ ] **Step 5: Commit `feat: devices and env subcommands for the GUI`**

### Task 3: session and model frontmatter

**Files:**
- Modify: `callscribe` (process_session), `tests/t_process.sh`

**Interfaces:**
- Produces: transcript frontmatter gains `session: <session id>` and `model: <basename of CALLSCRIBE_MODEL>` lines between `sys_device:` and the warnings list.

- [ ] **Step 1: Add to t_process.sh:** the first transcript contains `^session: 20260101-120000$` and `^model: model.bin$`
- [ ] **Step 2: Run it; expected: FAIL**
- [ ] **Step 3: Implement in process_session**
- [ ] **Step 4: Run `make test`; expected: PASS**
- [ ] **Step 5: Commit `feat: session and model provenance in transcript frontmatter`**

### Task 4: GUI core logic (headless)

**Files:**
- Create: `callscribe-gui` (mode 755, `#!/usr/bin/env python3`), `tests/test_gui.py`

**Interfaces:**
- Produces, as module-level functions in `callscribe-gui` (tests load it with `importlib.machinery.SourceFileLoader("callscribe_gui", path)`; the file touches Tk only inside `main()` under `if __name__ == "__main__":`):
  - `parse_devices(text: str) -> list[dict]`: dicts with keys kind, name, desc, flags (a set), from Task 2's format.
  - `parse_env(text: str) -> dict[str, str]`: strips the `CALLSCRIBE_` prefix in keys.
  - `parse_status(text: str) -> tuple[str, str | None, int | None]`: `("idle", None, None)`, `("recording", session, elapsed_seconds)`, or `("unknown", None, None)` for anything else.
  - `parse_links(pw_link_text: str, mic_dev: str, sys_dev: str) -> tuple[bool, bool]`: whether a pw-record input is linked to mic capture ports and to the sink's monitor ports.
  - `read_frontmatter(path: str) -> dict`: plain `key: value` lines between `---` fences, stdlib only, missing or fence-less file gives `{}`.
  - `list_transcripts(out_dir: str, sessions_dir: str) -> list[dict]`: newest-first `*-call*.md` (excluding `*.summary.md`), each dict: path, date, start, duration_seconds (int or None), session (or None), model (or None), rerunnable (bool: session known and its dir still holds `mic.wav` or `sys.wav`). Missing out_dir gives `[]`.
  - `set_config_values(path: str, values: dict[str, str]) -> None`: rewrites `KEY='value'` lines in the sh config, replacing a line whose key matches, appending absent keys at the end, leaving every other line byte-identical; creates file and parent dir when absent.
  - `medium_model_path(model_path: str) -> str`: `ggml-medium.bin` beside the configured model.

- [ ] **Step 1: Write `tests/test_gui.py`** (one test per behavior, fixtures as literal strings/temp dirs): parse_devices on Task 2's four-column format including flags; parse_env round trip; parse_status on idle, `recording 20260101-120000 754s`, and garbage (Review Focus 4); parse_links true/true on a fixture modeled on real pw-link output, false for a missing link; read_frontmatter on a real transcript fixture and on a file with no fences; list_transcripts ordering, summary exclusion, pre-GUI file without session giving rerunnable False (Review Focus 2), missing dir giving [] (Review Focus 5), cleaned session (dir without wavs) giving rerunnable False; set_config_values preserving comments and unrelated lines byte-identical while updating one key and appending another (Review Focus 1); medium_model_path
- [ ] **Step 2: Run `python3 -m unittest discover -s tests`; expected: FAIL (file missing)**
- [ ] **Step 3: Implement the functions in `callscribe-gui` with a stub `main()`**
- [ ] **Step 4: Run `make test`; expected: PASS**
- [ ] **Step 5: Commit `feat: GUI core logic, headless`**

### Task 5: Tk layer

**Files:**
- Modify: `callscribe-gui`, `Makefile` (install both new executables)

**Interfaces:**
- Consumes: every Task 4 function, `callscribe env/devices/status/start/stop/transcribe/summarize`.
- Produces: `main()`: tkinter import guarded (exit 1 naming the tk package); single instance via `<state_dir>/gui.pid` (alive pid: try `wmctrl -x -a callscribe`, then exit 0); `tk.Tk(className="callscribe")`, dark monospace styling per the mockup; layout B: state line with dot, big timer, two ttk.Combobox device pickers (descriptions shown, node names stored, a "(system default)" first entry storing empty), START/STOP buttons with the inactive one disabled, transcript rows with open/summarize/re-run medium buttons. A 1 second `after()` tick re-reads status; picker changes call set_config_values immediately; START refuses with a red picker warning while a `missing` flag is present; STOP and the row actions run their CLI calls on a worker thread posting back through a queue the tick drains, with a "processing..." state until the subprocess returns; the links check runs once about a second after a start is observed and sets "both streams linked" or a warning line. Open uses `$TERMINAL -e $EDITOR <file>` when both are set, else `xdg-open`; summarize writes `<name>.summary.md` beside the transcript and opens it; re-run medium is disabled when not rerunnable or `medium_model_path` is absent, with a one-line reason.

- [ ] **Step 1: Implement main() and the App class**
- [ ] **Step 2: Verify headless-safe: `python3 -c "import importlib.machinery as m; m.SourceFileLoader('g','callscribe-gui').load_module()"` on a box with DISPLAY unset; expected: no Tk window, exit 0**
- [ ] **Step 3: Run `make test`; expected: PASS (no regressions)**
- [ ] **Step 4: Commit `feat: callscribe-gui tkinter window`**

### Task 6: bar block and contrib

**Files:**
- Create: `sb-callscribe`, `contrib/blocks.h.snippet`, `contrib/dwm-rule.snippet`, `tests/t_bar.sh`
- Modify: `Makefile` (install sb-callscribe), `README.md`, `contrib/dwm-keybind.diff.example` (signal 12), delete `contrib/dwmblocks-callscribe.sh`

**Interfaces:**
- Consumes: `callscribe status` / `toggle`; `callscribe-gui`.
- Produces: `sb-callscribe` prints a quiet idle glyph when idle and a red-dot marker with `mm:ss` elapsed while recording; `BLOCK_BUTTON=1` spawns `callscribe-gui` detached (`setsid -f`), `BLOCK_BUTTON=3` runs `setsid -f sh -c 'callscribe toggle; pkill -RTMIN+12 dwmblocks'` so a minutes-long stop never blocks the bar. `contrib/blocks.h.snippet` carries the block line (interval 10, signal 12); `contrib/dwm-rule.snippet` the float rule for class "callscribe". README gains a GUI and bar section listing the tk dependency and the two sudo recompile steps.

- [ ] **Step 1: Write `tests/t_bar.sh`** (stubbed callscribe and callscribe-gui on PATH, STUB_LOG assertions): idle prints no red marker; a status of `recording x 754s` prints the marker and `12:34`; BLOCK_BUTTON=1 spawns the gui exactly once; BLOCK_BUTTON=3 invokes toggle and the RTMIN+12 signal without the script itself blocking (returns within a second against a slow stub)
- [ ] **Step 2: Run it; expected: FAIL**
- [ ] **Step 3: Implement sb-callscribe, both snippets, Makefile and README changes, delete the superseded contrib module**
- [ ] **Step 4: Run `make test`; expected: PASS**
- [ ] **Step 5: Commit `feat: sb-callscribe bar block and dwm contrib`**

### Task 7: live install and click-through (interactive, with Timothy)

**Files:**
- Modify: this machine's `~/.local/src/dwmblocks/config.h` and `~/.local/src/dwm/config.h` (user applies, sudo recompiles)

- [ ] **Step 1: `make install`; add the blocks.h line and the dwm rule from contrib; Timothy runs the two `sudo make clean install` builds and restarts dwm**
- [ ] **Step 2: Bar shows the idle glyph; left-click opens the floating window, centered and floating (not tiled)**
- [ ] **Step 3: Click START in the window: dot goes red, timer ticks, "both streams linked" appears, bar shows the marker and elapsed**
- [ ] **Step 4: Right-click the bar block: recording toggles off, "processing..." resolves to a new row at the top of the list; open and summarize both work from the row**
- [ ] **Step 5: Unplug test: set a picker to a bogus saved device via config, confirm START is blocked with the warning, then fix it from the picker and confirm the fix persisted to config**
- [ ] **Step 6: Commit any contrib corrections found live; `docs:` commit for README adjustments**

---

## Self-review notes

Spec coverage: bar block (Task 6), window layout and all states (5), pickers with persistence (4, 5), device overrides and loud missing failure (1), devices/env (2), provenance and labeled re-run (3, 4, 5), keep-both (existing collision naming, 3), medium-absent handling (4, 5), single instance (5), contrib and README (6), live verification (7). Interface names cross-checked between Tasks 2, 4, 5 and 6. Review Focus items each name their owning task. The `env` subcommand is this plan's addition so the GUI never re-implements config sourcing; it extends the spec's "keeps all pactl parsing in one place" reasoning to config.

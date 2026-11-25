# callscribe GUI and Aegix bar block (design)

Date: 2026-11-24
Status: draft, awaiting Timothy's approval
Builds on: 2026-11-24-callscribe-design.md (the CLI, already shipped)

## Intent and why

callscribe works from the CLI and a keybind, but the moment that matters is a
rushed one: a meeting just started, or Timothy remembers mid-call that he wants
a transcript. He wants a mouse-first path that is obvious under pressure:
glance at the Aegix top bar, click, see unmistakably that recording is running,
and later stop it just as unmistakably. Everything else callscribe does
(transcripts, summaries, re-runs, fixing devices) hangs off that window as a
secondary layer. Built in the callscribe repo so other Aegix users get it.

## Goals

- A dwmblocks block showing recording state at a glance, updating while
  recording.
- Click the block to open a small floating window; a second, faster click
  action toggles recording without opening anything.
- The window makes start, validate, stop the dominant flow: big state line,
  big timer, a live "both streams linked" check, START/STOP buttons with the
  inactive one dimmed (layout B from the mockups, Timothy's pick).
- Device pickers for you/them so wrong routing can be fixed from the window;
  changes are saved to the callscribe config immediately and steer future
  recordings (Timothy's pick: always saved).
- Secondary layer: recent transcripts with open, summarize, and re-run with
  the medium model.
- Works on any Aegix/PipeWire box, not just this machine.

## Non-goals (v1)

- Changing devices mid-recording (pickers lock while recording).
- Live transcription view, audio level meters, waveforms.
- Echo cancellation, mobile, anything from the CLI design's non-goals.
- A tray icon or any daemon; the window is a process that runs while open.

## Anti-goals

- New runtime dependencies beyond what Aegix ships: no pip packages, no venv,
  no GTK/Qt bindings. Python stdlib only.
- Surprise persistence anywhere except the one Timothy chose: device changes
  write to config immediately; nothing else writes config.

## Constraints

- GUI: Python 3 stdlib tkinter, one file, no venv. If tkinter is missing
  (minimal installs without the tk package), exit with a clear message naming
  the package to install. README lists tk as a dependency.
- Bar script: POSIX sh, named `sb-callscribe`, following the conventions of
  the 27 existing sb-* scripts in ~/.local/bin (BLOCK_BUTTON click handling).
- dwm already routes status bar clicks via sigdwmblocks (verified in this
  machine's config.h); dwmblocks sets BLOCK_BUTTON (verified in dwmblocks.c).
  Free update signal 12 is used (1,2,3,4,5,9,10,11,14,18 are taken here).
- The window floats via a dwm rule on its WM_CLASS; instance/class is
  "callscribe". The rule and the blocks.h entry ship as contrib snippets plus
  README instructions; recompiling dwm/dwmblocks is the user's action (sudo).
- No em or en dashes anywhere. All callscribe CLI conventions carry over.
- All tests runnable headless (no X required): GUI logic that is testable
  (state model, config writing, device parsing, transcript listing) lives in
  functions importable without creating a Tk root; the Tk layer stays thin.

## Approaches considered

1. **Python stdlib tkinter (picked).** No new deps, live-updating stateful UI
   is natural, exact dark monospace styling, className for the float rule.
2. **yad dialogs.** Already installed but wrong shape for a stateful window
   with a ticking timer and locking controls; rejected.
3. **Floating st + shell TUI.** Most suckless, but mouse-first was the point
   and TUI mouse plus dropdowns is janky; rejected.

## The how (decided)

Calls marked (TB) are Timothy's from the mockup conversation; the rest are
the designer's calls, open to correction.

- **(TB) Window layout: the B "status console"** from the mockups: title
  strip, state line with dot, big timer, device rows, START/STOP side by
  side with the inactive one dimmed, recent-transcripts list below. The
  approved mockup is preserved beside this doc as
  `2026-11-24-callscribe-gui-mockup.html`; its idle and recording panes are
  the acceptance target for structure and tone, not pixel exactness.
- **(TB) Device pickers** for you (sources) and them (sinks), populated from
  pactl, editable while idle, disabled while recording.
- **(TB) Device changes are saved immediately** to the callscribe config and
  steer every future recording until changed again.
- **(TB) GUI tech: tkinter, stdlib only, no venv.**
- **CLI growth (new):** `callscribe` learns `CALLSCRIBE_MIC_DEV` and
  `CALLSCRIBE_SYS_DEV` config variables. When set and non-empty, `start`
  records those devices instead of the pactl defaults; empty or unset keeps
  today's default-device behavior. The GUI writes exactly these two variables
  into `~/.config/callscribe/config`, preserving other lines.
- **Configured device missing (designer's call, from builder review):** if a
  configured device is not present at `start`, die loudly naming the device
  and the config variable; never fall back silently (that is the exact
  failure the routing safety exists to prevent). `callscribe devices` flags
  a configured-but-missing device, and the GUI blocks START with a visible
  warning on the offending picker until it is fixed.
- **Transcript provenance (designer's call, from builder review):** the
  frontmatter `process_session` writes gains two fields, `session:` (the
  session id) and `model:` (the model file's basename). The transcript list
  uses `session:` to drive re-run and shows a small/medium tag from
  `model:`. Rows without these fields (pre-GUI transcripts) and rows whose
  session audio is gone (after `callscribe clean`) show re-run disabled.
- **(TB) Re-run keeps both transcripts:** the medium result is written as a
  sibling file (existing collision naming), never replacing the original;
  the model tag is how the two are told apart in the list.
- **Medium model absent (designer's call, from builder review):** the re-run
  action looks for ggml-medium.bin beside the configured model; when absent,
  the button is disabled with a short line telling the user to run
  `callscribe setup` for it in a terminal. The GUI never downloads models.
- **New `callscribe devices` subcommand:** machine-readable listing the GUI
  consumes: one line per device, `kind<TAB>node-name<TAB>description`, kinds
  `source` and `sink`, from `pactl list` (descriptions, so the dropdown can
  show "Volt 176 mic" rather than raw node names), with the current effective
  choice marked. Keeps all pactl parsing in one place, testable from sh.
- **Window behavior:** polls `callscribe status` (and session meta) on a 1s
  tick for state and timer; the "both streams linked" check runs pw-link
  against the session's device names shortly after start and shows a check
  or a loud warning line. STOP runs `callscribe stop` in a subprocess with a
  visible "processing..." state until the transcript path comes back, then
  refreshes the list and shows the new file on top. Window title and state
  strip reflect idle / recording / processing.
- **Transcript list:** newest first from CALLSCRIBE_OUT_DIR, showing date,
  start time, and duration from the frontmatter. Row actions: open (spawn
  the file via $TERMINAL -e $EDITOR when both are set, else xdg-open),
  summarize (runs `callscribe summarize`, saves the output next to the
  transcript as <name>.summary.md and opens it the same way), re-run medium
  (runs transcribe with CALLSCRIBE_MODEL pointed at ggml-medium.bin).
- **Bar block `sb-callscribe`:** prints nothing when idle beyond a small
  idle glyph, and a red-dot marker plus mm:ss elapsed while recording;
  10 second interval plus signal 12 for instant refresh. BLOCK_BUTTON 1
  opens the window (single instance: a pidfile under the callscribe state
  dir; if alive, try `wmctrl -x -a callscribe` to focus, else do nothing),
  BLOCK_BUTTON 3 runs `callscribe toggle` and signals the bar. The existing
  keybind contrib gains the same signal-12 refresh.
- **Files:** `callscribe-gui` (python, installed by make install),
  `sb-callscribe` (sh, installed by make install), contrib gains the dwm
  float-rule snippet and the blocks.h entry snippet; README gains a GUI and
  bar section. The old contrib dwmblocks module is superseded by
  sb-callscribe and removed.

## Left to the builder

- Exact widget styling to approximate the mockup (colors, monospace font
  choice, padding); Tk ttk vs classic widgets.
- Frontmatter parsing for the list (tiny, stdlib, no yaml dependency).
- How the 1s tick and subprocess calls stay off the Tk main thread
  (after() scheduling vs a worker thread).
- pw-link output parsing for the linked check, and its failure wording.
- Config rewriting mechanics (preserve comments and unrelated lines).
- Behavior when CALLSCRIBE_OUT_DIR is empty or missing (empty list, no
  crash).

## Success looks like

Mid-scramble before a huddle, Timothy clicks the bar once, hits the big
green START, sees the dot go red, the timer tick, and "both streams
linked", and gets on with the call. The bar shows REC 12:41 all meeting.
Afterward one click stops it, "processing..." resolves into the new
transcript at the top of the list, and one more click sends it to Claude
for follow-ups. A wrong device is a dropdown fix that sticks.

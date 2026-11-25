# callscribe

Record both sides of any call audible on a PipeWire Linux machine (a Slack
huddle, a Teams call in the browser, Zoom, anything), transcribe it locally
with whisper.cpp, and get one timestamped Markdown transcript with You/Them
speaker labels. No bot joins the meeting, no audio leaves the machine.

**Headset required.** The speaker labels work because your microphone and
your system audio are recorded as two separate streams. On open speakers the
microphone hears the far end too and the labels silently degrade. Use a
headset.

**Consent.** Recording the people you talk to is a legal and workplace-policy
question before it is a technical one. callscribe records only when you start
it, and you are responsible for complying with the recording laws of your
jurisdiction and the policies of your workplace.

## Dependencies

- PipeWire with pipewire-pulse (`pw-record`, `pactl`)
- ffmpeg
- whisper.cpp (`whisper-cli`) and a ggml model: `callscribe setup` installs both
- Python 3 (standard library only, for the transcript merge)
- Optional: the `claude` CLI for `callscribe summarize`

## Install

```
make install          # copies callscribe and callscribe-merge to ~/.local/bin
callscribe setup      # builds whisper.cpp in ~/.local/src, downloads a model
```

## Usage

```
callscribe start      # prints which devices it is recording; check them
callscribe status     # recording <session> <elapsed>s, or idle
callscribe stop       # transcribes and prints the Markdown file path
callscribe toggle     # start if idle, stop if recording (bind this to a key)
callscribe transcribe <session-id>   # rerun processing on a finished session
callscribe clean      # delete raw WAVs from finished sessions
callscribe summarize <transcript.md> # pipe a transcript to the claude CLI
```

A transcript looks like:

```
---
date: 2026-11-24
start: 14:00
duration_seconds: 1860
mic_device: alsa_input.usb-...
sys_device: alsa_output.usb-...
---

**[0:00:04] Them:** Can you hear me now?
**[0:00:06] You:** Loud and clear.
```

## Configuration

Optional file at `~/.config/callscribe/config`, plain shell assignments.
Environment variables with the same names override it.

| Variable | Default | Meaning |
|---|---|---|
| `CALLSCRIBE_OUT_DIR` | `~/Documents/PERSONAL/meetings` | where transcripts land |
| `CALLSCRIBE_MODEL` | `~/.local/share/callscribe/models/ggml-small.bin` | ggml model path |
| `CALLSCRIBE_WHISPER_BIN` | `whisper-cli` | whisper.cpp binary |
| `CALLSCRIBE_LANG` | `en` | transcription language |
| `CALLSCRIBE_SILENCE_DB` | `-50` | mean volume below this warns of a silent stream |
| `CALLSCRIBE_WHISPER_FLAGS` | empty | extra whisper-cli flags, e.g. `-t 8` for 8 threads |
| `CALLSCRIBE_CLAUDE_BIN` | `claude` | CLI used by `summarize` |

Raw audio and working files live under `~/.local/state/callscribe/sessions/`
until you run `callscribe clean`, so a call can be re-transcribed with a
bigger model at any time.

## GUI and the Aegix top bar

`callscribe-gui` is a small floating window (tkinter, Python stdlib, no
venv; needs the distro `tk` package) built for the rushed moment: a state
dot, a big timer, a "both streams linked" check, START/STOP with the
inactive one dimmed, device pickers for you/them (saved to the config the
moment you change them, locked while recording), and a recent-transcripts
list with open, summarize, and re-run-with-medium actions.

`sb-callscribe` is the matching dwmblocks block: a quiet glyph when idle,
a red marker with elapsed time while recording. Left-click opens the
window, right-click toggles recording without opening anything.

Wiring it into the bar (both need sudo rebuilds):

1. Add the line from `contrib/blocks.h.snippet` to your dwmblocks
   `config.h` (signal 12, interval 10), rebuild dwmblocks.
2. Add the rule from `contrib/dwm-rule.snippet` to your dwm `config.h` so
   the window floats, rebuild dwm.
3. Optional keyboard path: `contrib/dwm-keybind.diff.example` binds one
   key to toggle plus bar refresh.

## dwm keybinding

See `contrib/dwm-keybind.diff.example` for a one-key toggle.

## Benchmarks

Measured on an i7 laptop CPU (4 cores, 8 threads), processing both streams
of a 29 second call (58 seconds of audio total):

| Model | Wall time | Rough cost per call hour |
|---|---|---|
| ggml-small (default) | 18s (0.6x call length) | about 37 min |
| ggml-medium | 47s (1.6x call length) | about 97 min |

A second run with continuous speech on both streams came in at 1.3x call
length, so expect something between 0.6x and 1.5x depending on how dense
the talking is.

Adding `-t 8` was not faster than the default 4 threads on this CPU
(hyperthread contention). On clean call audio, medium's output was not
meaningfully better than small's; point `CALLSCRIBE_MODEL` at medium per
run for calls that deserve the extra accuracy.

## Known limitations

- Changing the default audio device mid-call is not handled; the recording
  follows the devices chosen at `callscribe start` (which it prints).
- Far-end speakers are labeled Them collectively; telling two remote
  speakers apart would need real diarization.
- Live transcription is out of scope; processing happens after the call.

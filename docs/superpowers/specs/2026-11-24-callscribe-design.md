# callscribe: local call transcription for Linux (design)

Date: 2026-11-24
Status: draft, awaiting Timothy's approval

## Intent and why

Timothy takes work calls in Slack huddles, Microsoft Teams (browser), and Zoom on his Aegix Linux machine. He wants transcripts of those calls as plain Markdown so he can feed them to an LLM for follow-ups and running context. He chose silent local capture over bot-based services (bots cannot join Slack huddles, corporate tenants may block them, and he prefers keeping audio on his own machine). He explicitly chose to build a small tool of his own rather than adopt tapeback, partly for control and partly so the result can serve the wider Aegix Linux community.

## Goals

- Capture both sides of any call audible on this machine: microphone (his voice) and system audio (everyone else), regardless of which app carries the call.
- Produce a timestamped Markdown transcript with "You" and "Them" attribution.
- Simple start/stop: a CLI first, with optional dwm keybind and dwmblocks recording indicator.
- Fully local transcription. No audio or text leaves the machine unless Timothy pipes it somewhere himself.
- Portable across Aegix/Artix systems: PipeWire assumed, audio devices auto-detected from the defaults, nothing hardcoded to this machine (the Volt 176 interface is detected, not assumed).
- Output lands somewhere durable and is clean input for an LLM.

## Non-goals (v1)

- Mobile capture. Desktop only, as agreed.
- Live/real-time transcription. Processing happens after the call ends.
- True multi-speaker diarization (telling apart two far-end speakers). v1 gives You/Them only, via the two-stream trick below. pyannote-style diarization can be a later bolt-on.
- A GUI. CLI, keybind, and status-bar indicator only.

## Anti-goals

- Anything that requires a cloud service for the core record-and-transcribe path.
- A visible bot or anything participants can see.
- Heavy frameworks (Electron/Tauri apps, daemons with their own config languages). This should feel like a suckless tool.

## Constraints

- Aegix Linux (Artix-based, runit), zsh as interactive shell. Scripts carry explicit `#!/bin/sh` or `#!/usr/bin/env bash` shebangs and are run as files, never pasted bash-isms.
- PipeWire with pipewire-pulse compat (pactl works; pw-record available).
- GPU is a Quadro M2000M (Maxwell, 4GB): not worth fighting for. Transcription runs on CPU (8 cores, 62GB RAM). A call processed in a few minutes after it ends is acceptable.
- Recording colleagues carries consent obligations. The tool is manual-start only (no auto-record), and the README will say plainly that the operator is responsible for complying with recording laws and workplace policy.
- **(TB) Headset-only in v1.** Timothy always takes calls on a headset, so the mic never hears the far end and the two-stream You/Them attribution holds. Echo cancellation (PipeWire echo-cancel module) is explicitly future work for speaker setups; the README documents the headset requirement.

## Approaches considered

1. **tapeback (off-the-shelf open source).** Right shape, AUR-packaged, but a young single-maintainer project. Timothy chose not to depend on it.
2. **Meetily (local full app).** Rejected: build-from-source Tauri app, UI-centric, fights the suckless workflow.
3. **Roll our own (picked).** A small CLI around pw-record and whisper.cpp. More initial work, full control, Aegix-shareable.

## The how (decided)

Calls marked (TB) were decided by Timothy in conversation; the rest are the designer's calls, open to correction.

- **(TB) Build our own tool; local capture; desktop first.**
- **Name: `callscribe`** (designer's call; trivially renameable).
- **ASR engine: whisper.cpp** (`whisper-cli`), built from source or AUR. C/C++, no Python dependency chain, fits the suckless ethos, excellent CPU performance with quantized models. Default model `small` or `medium` quantized; builder benchmarks a real recording and picks the default, configurable.
- **Capture: two parallel `pw-record` streams**, one from the default source (mic) and one from the default sink's monitor (system audio), to two WAV files. Keeping them separate is what gives You/Them attribution for free.
- **Routing safety (designer's call, prompted by builder review):** `start` snapshots the default source and sink by name and records those named devices, prints them so a wrong target is visible immediately, and `stop` runs a cheap silence check on both WAVs, warning loudly if either stream is effectively empty (the "recorded the wrong sink" failure). A default-device change mid-call is a documented v1 limitation, not handled.
- **Attribution by merge:** transcribe each WAV separately with timestamps, then interleave the two transcripts by timestamp into one Markdown document, labeling mic segments "You" and monitor segments "Them".
- **Preprocessing:** ffmpeg resamples to 16 kHz mono WAV as whisper.cpp expects.
- **CLI surface:** `callscribe start`, `callscribe stop`, `callscribe status`, `callscribe transcribe <session>` (rerun/offline processing), `callscribe summarize <note>` (optional helper that pipes the note into `claude -p` with a follow-up prompt; the core tool never calls an LLM on its own).
- **State:** in-progress sessions under `~/.local/state/callscribe/sessions/<timestamp>/`. A state file exposes recording status for dwmblocks.
- **Output:** Markdown with YAML frontmatter (date, start time, duration, devices) plus interleaved transcript, written to `~/Documents/PERSONAL/meetings/` by default, configurable. Raw WAVs kept beside the session until explicitly cleaned (`callscribe clean`), since re-transcription with a better model is cheap and the audio is the ground truth.
- **Config:** optional `~/.config/callscribe/config` (sourced shell variables: output dir, model, language, extra whisper flags). Sensible defaults mean zero config to start.
- **Language: POSIX-leaning shell** for the CLI and capture control; if the timestamp merge proves too awkward in awk, a single small Python script (stdlib only) is acceptable for the merge step alone.
- **Integration (optional, documented, not auto-installed):** a dwm keybind snippet for config.h and a dwmblocks module showing a recording dot.
- **Repo and license:** new git repo at `~/code/callscribe`, MIT license, written so it can later publish to the aegixlinux GitHub org and the AUR via the existing packaging workflow.

## Left to the builder

- Benchmark and choose the default whisper.cpp model and quantization for 8-core CPU; document realistic processing time per call hour.
- Exact merge algorithm (segment granularity, how to render overlapping speech, timestamp format in the Markdown).
- Handling very long calls (chunking if needed) and disk hygiene rules.
- Whether `pw-record` or `parecord` behaves better for the monitor stream; detect defaults via `pactl get-default-source` / `get-default-sink`.
- Failure behavior: machine suspend mid-call, device unplugged, stop without start.

## Success looks like

Timothy hits a keybind before a huddle, hits it again after, and within a few minutes a Markdown file exists with a readable You/Them transcript good enough to paste into Claude for "write my follow-ups". The same scripts run unmodified on another Aegix box.

#!/bin/sh
# dwmblocks module for callscribe: prints a recording marker while a
# recording is running, nothing when idle.
#
# Install: copy somewhere on PATH (e.g. ~/.local/bin/dwmblocks-callscribe)
# and add a block to your dwmblocks config.h, for example:
#
#   { "", "dwmblocks-callscribe", 5, 10 },
#
# The keybinding in dwm-keybind.diff.example signals RTMIN+10 after a
# toggle so the indicator updates immediately.
case "$(callscribe status 2>/dev/null)" in
recording*) printf 'REC\n' ;;
*) ;;
esac
exit 0

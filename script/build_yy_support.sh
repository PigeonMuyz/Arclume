#!/bin/bash
# Rebuild the reviewed YY helper; Wine itself is never built here.
set -euo pipefail
support_root="$(cd "$(dirname "$0")/.." && pwd)"
support_output="$support_root/Arclume/Resources/yy-launch-support.exe"
x86_64-w64-mingw32-gcc -Wall -Wextra -Werror -O2 -municode -mwindows \
    -DYY_LAUNCH_SUPPORT=1 -Wl,--no-insert-timestamp \
    "$support_root/script/diagnostics/yy_dns_probe.c" -o "$support_output" -lbcrypt -lpsapi -lshell32
shasum -a 256 "$support_output"
echo 'Update YYLaunchSupport.helperSHA256 after reviewing the source and verifying this build.'

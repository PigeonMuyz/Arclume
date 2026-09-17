#!/bin/bash
set -euo pipefail
warmup_root="$(cd "$(dirname "$0")/.." && pwd)"
x86_64-w64-mingw32-gcc -Wall -Wextra -Werror -O2 -municode -mwindows \
    -Wl,--no-insert-timestamp "$warmup_root/script/wine_keepalive.c" \
    -o "$warmup_root/Arclume/Resources/wine-keepalive.exe"
shasum -a 256 "$warmup_root/Arclume/Resources/wine-keepalive.exe"
echo 'Review and update WineWarmupService.helperSHA256 after rebuilding.'

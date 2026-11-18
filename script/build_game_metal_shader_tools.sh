#!/bin/bash
set -euo pipefail

# Native Metal preparation for DXMT v0.80's observed cache_18 libraries.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
output_dir="${1:-$repo_root/Arclume/Resources/GameMetalShaderTools}"
mingw="${ARCLUME_DXBC_MINGW:-x86_64-w64-mingw32-g++}"
if ! command -v "$mingw" >/dev/null || ! command -v brew >/dev/null || ! brew list --versions zstd >/dev/null; then
    printf '%s\n' 'Install the build dependencies with brew install mingw-w64 zstd.' >&2
    exit 1
fi
zstd=$(brew --prefix zstd)
mkdir -p "$output_dir"
xcrun clang++ -std=c++17 -O2 -Wall -Wextra -Werror -mmacosx-version-min=26.0 \
    -I "$zstd/include" "$repo_root/script/jx3-shader-tools/jx3-shader-scan.cpp" \
    "$zstd/lib/libzstd.a" -o "$output_dir/jx3-shader-scan"
"$mingw" -std=c++20 -O2 -static -Wall -Wextra -Werror \
    "$repo_root/script/metal-shader-tools/game-dxbc-compile.cpp" -ld3d11 -lbcrypt \
    -o "$output_dir/game-dxbc-compile.exe"
install -m 644 "$zstd/LICENSE" "$output_dir/Zstandard-LICENSE.txt"
install -m 644 "$repo_root/script/metal-shader-tools/DXMT-LICENSE.txt" "$output_dir/DXMT-LICENSE.txt"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-deprecated-declarations \
    -mmacosx-version-min=26.0 -arch arm64 -arch x86_64 \
    "$repo_root/script/metal-shader-tools/game-metal-shader-cache.m" \
    -framework Foundation -framework Metal -lsqlite3 \
    -o "$output_dir/game-metal-shader-cache"
signing_identity="${ARCLUME_METAL_TOOLS_SIGNING_IDENTITY:--}"
if [[ -z "$signing_identity" || "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$output_dir/game-metal-shader-cache"
    codesign --force --sign - "$output_dir/jx3-shader-scan"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$output_dir/game-metal-shader-cache"
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$output_dir/jx3-shader-scan"
fi
codesign --verify --strict "$output_dir/game-metal-shader-cache"
codesign --verify --strict "$output_dir/jx3-shader-scan"

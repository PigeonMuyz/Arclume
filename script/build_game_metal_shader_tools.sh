#!/bin/bash
set -euo pipefail

# Native Metal preparation for DXMT v0.80's observed cache_18 libraries.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
output_dir="${1:-$repo_root/Arclume/Resources/GameMetalShaderTools}"
mingw="${ARCLUME_DXBC_MINGW:-x86_64-w64-mingw32-g++}"
if ! command -v "$mingw" >/dev/null; then
    printf '%s\n' 'Install the Windows cross-compiler with brew install mingw-w64.' >&2
    exit 1
fi

# A Homebrew library only contains its host architecture. Build each scanner
# slice against the same pinned upstream source and combine the executables.
temporary=$(mktemp -d "${TMPDIR:-/tmp}/arclume-shader-tools.XXXXXX")
trap 'find "$temporary" -depth -delete' EXIT
zstd_version=1.5.7
zstd_sha256=37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3
zstd_archive="$temporary/zstd.tar.gz"
curl --fail --silent --show-error --location --proto '=https' --retry 2 \
    --output "$zstd_archive" "https://github.com/facebook/zstd/archive/refs/tags/v$zstd_version.tar.gz"
printf '%s  %s\n' "$zstd_sha256" "$zstd_archive" | shasum -a 256 -c -
tar -xzf "$zstd_archive" -C "$temporary"
zstd="$temporary/zstd-$zstd_version"
clang=$(xcrun --find clang)
ar=$(xcrun --find ar)
sdk=$(xcrun --sdk macosx --show-sdk-path)
jobs=$(sysctl -n hw.activecpu)

mkdir -p "$output_dir"
for architecture in arm64 x86_64; do
    SDKROOT="$sdk" make -s -C "$zstd/lib" -j "$jobs" CC="$clang" AR="$ar" \
        BUILD_DIR="$temporary/zstd-build-$architecture" \
        CFLAGS="-O2 -arch $architecture -mmacosx-version-min=26.0" libzstd.a
    xcrun clang++ -std=c++17 -O2 -Wall -Wextra -Werror -mmacosx-version-min=26.0 \
        -arch "$architecture" -I "$zstd/lib" "$repo_root/script/jx3-shader-tools/jx3-shader-scan.cpp" \
        "$zstd/lib/libzstd.a" -o "$temporary/jx3-shader-scan-$architecture"
done
xcrun lipo -create "$temporary/jx3-shader-scan-arm64" "$temporary/jx3-shader-scan-x86_64" \
    -output "$output_dir/jx3-shader-scan"
xcrun lipo "$output_dir/jx3-shader-scan" -verify_arch arm64
xcrun lipo "$output_dir/jx3-shader-scan" -verify_arch x86_64
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

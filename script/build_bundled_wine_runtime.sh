#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_SOURCE_DIR="$ROOT_DIR/RuntimeSource"
LOCK_FILE="$RUNTIME_SOURCE_DIR/CROSSOVER_SOURCE.lock"
SOURCE_DIR="$RUNTIME_SOURCE_DIR/wine"
BUILD_DIR="$RUNTIME_SOURCE_DIR/build/wine-x86_64"
DIST_DIR="$RUNTIME_SOURCE_DIR/dist"
BASE_ARCHIVE="$ROOT_DIR/Procyon/Resources/OnlineGameDependencies/procyon-wine-runtime-x86_64-v8-mono.tar.xz"
RUNTIME_VERSION_RESOURCE="$ROOT_DIR/Procyon/Resources/OnlineGameDependencies/procyon-wine-runtime-version.txt"
RUNTIME_ROOT="procyon-wine-runtime-x86_64-v8-mono-d3dmetal4-zhcn"
DEFAULT_OUTPUT="$DIST_DIR/procyon-wine-runtime-x86_64-v8-mono-wine11-rebuilt.tar.xz"

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "Missing source lock file: $LOCK_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$LOCK_FILE"

clean_build=false
output_path="$DEFAULT_OUTPUT"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      clean_build=true
      ;;
    --output)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--output requires a path" >&2
        exit 2
      fi
      output_path="$1"
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: ./script/build_bundled_wine_runtime.sh [--clean] [--output PATH]

Builds the locked x86_64 Wine source, overlays its install output onto a fresh
copy of the currently shipped runtime archive, and writes a candidate .tar.xz.

  --clean        Remove only RuntimeSource/build/wine-x86_64 before configuring.
  --output PATH  Candidate archive destination (must not already exist).

The current App resource is never overwritten. The script does not access or
modify game prefixes under ~/Library/Application Support/Procyon.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$output_path" != /* ]]; then
  output_path="$ROOT_DIR/$output_path"
fi

for tool in /usr/bin/xcrun /usr/bin/make /usr/bin/tar /usr/bin/shasum; do
  if [[ ! -x "$tool" ]]; then
    echo "Required build tool is unavailable: $tool" >&2
    exit 1
  fi
done

if [[ ! -x "$SOURCE_DIR/configure" || ! -f "$SOURCE_DIR/VERSION" ]]; then
  echo "Wine source is not ready. Run ./script/sync_crossover_wine_source.sh first." >&2
  exit 1
fi

if [[ "$(<"$SOURCE_DIR/VERSION")" != "Wine version $WINE_VERSION" ]]; then
  echo "Wine source version does not match the lock file." >&2
  exit 1
fi

if [[ ! -f "$BASE_ARCHIVE" ]]; then
  echo "Missing currently shipped runtime archive: $BASE_ARCHIVE" >&2
  exit 1
fi

if [[ ! -f "$RUNTIME_VERSION_RESOURCE" ]]; then
  echo "Missing runtime version resource: $RUNTIME_VERSION_RESOURCE" >&2
  exit 1
fi

runtime_version="$(/usr/bin/tr -d '[:space:]' < "$RUNTIME_VERSION_RESOURCE")"
if [[ -z "$runtime_version" || "$runtime_version" != "$RUNTIME_VERSION" ]]; then
  echo "Runtime version resource does not match CROSSOVER_SOURCE.lock." >&2
  echo "Lock:     $RUNTIME_VERSION" >&2
  echo "Resource: ${runtime_version:-<empty>}" >&2
  exit 1
fi

if [[ -e "$output_path" ]]; then
  echo "Refusing to overwrite existing candidate: $output_path" >&2
  exit 1
fi

run_x86() {
  if [[ "$(/usr/bin/uname -m)" == "arm64" ]]; then
    /usr/bin/arch -x86_64 "$@"
  else
    "$@"
  fi
}

if [[ "$(/usr/bin/uname -m)" == "arm64" ]] && ! /usr/bin/arch -x86_64 /usr/bin/true; then
  echo "Rosetta is required to build the x86_64 Wine runtime." >&2
  exit 1
fi

if [[ "$clean_build" == true && -e "$BUILD_DIR" ]]; then
  case "$BUILD_DIR" in
    "$ROOT_DIR"/RuntimeSource/build/wine-x86_64) ;;
    *)
      echo "Refusing to clean unexpected build path: $BUILD_DIR" >&2
      exit 1
      ;;
  esac
  /usr/bin/find "$BUILD_DIR" -depth -delete
fi

/bin/mkdir -p "$BUILD_DIR" "$(dirname "$output_path")"
sdk_root="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
# Keep the Wine loader compatible with the app's supported macOS generation.
# Passing this only to configure is insufficient: clang is invoked later by
# make, where Xcode otherwise defaults the Mach-O minimum version to its SDK.
deployment_target="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
jobs="${JOBS:-$(/usr/sbin/sysctl -n hw.ncpu)}"
host_cc="/usr/bin/gcc -arch x86_64"
host_cxx="/usr/bin/g++ -arch x86_64"
build_path="$PATH"
if [[ -x /opt/homebrew/opt/bison/bin/bison ]]; then
  build_path="/opt/homebrew/opt/bison/bin:$build_path"
elif [[ -x /usr/local/opt/bison/bin/bison ]]; then
  build_path="/usr/local/opt/bison/bin:$build_path"
fi

# Apple Silicon Homebrew libraries are arm64-only. When building the x86_64
# Wine host tools, reuse the x86_64 FreeType dylib already carried by the
# baseline runtime and pair it with Homebrew's architecture-neutral headers.
# The rebuilt runtime continues to ship that same dylib under lib64.
freetype_cflags="${FREETYPE_CFLAGS:-}"
freetype_libs="${FREETYPE_LIBS:-}"
build_dyld_fallback="${DYLD_FALLBACK_LIBRARY_PATH:-}"
build_ldflags="${LDFLAGS:-}"
compat_lib_dir="$BUILD_DIR/.procyon-x86_64-libs"
if [[ -f "$BASE_ARCHIVE" ]]; then
  /bin/mkdir -p "$compat_lib_dir"
  /usr/bin/tar -xJf "$BASE_ARCHIVE" -C "$compat_lib_dir" \
    --strip-components=2 \
    "$RUNTIME_ROOT/lib64/libMoltenVK.dylib" \
    "$RUNTIME_ROOT/lib64/libfreetype.6.20.2.dylib" \
    "$RUNTIME_ROOT/lib64/libfreetype.6.dylib"
  /bin/ln -sf libfreetype.6.dylib "$compat_lib_dir/libfreetype.dylib"
  build_ldflags="-L$compat_lib_dir${build_ldflags:+ $build_ldflags}"
  build_dyld_fallback="$compat_lib_dir${build_dyld_fallback:+:$build_dyld_fallback}"
fi
if [[ -z "$freetype_cflags" && -z "$freetype_libs" \
  && -f /opt/homebrew/opt/freetype/include/freetype2/ft2build.h ]]; then
  freetype_cflags="-I/opt/homebrew/opt/freetype/include/freetype2"
  freetype_libs="-L$compat_lib_dir -lfreetype"
fi

if [[ ! -f "$BUILD_DIR/Makefile" ]]; then
  echo "Configuring Wine $WINE_VERSION for x86_64..."
  (
    cd "$BUILD_DIR"
    run_x86 /usr/bin/env \
      PATH="/usr/local/bin:$build_path" \
      SDKROOT="$sdk_root" \
      MACOSX_DEPLOYMENT_TARGET="$deployment_target" \
      CC="$host_cc" \
      CXX="$host_cxx" \
      LDFLAGS="$build_ldflags" \
      FREETYPE_CFLAGS="$freetype_cflags" \
      FREETYPE_LIBS="$freetype_libs" \
      /bin/bash "$SOURCE_DIR/configure" \
      --enable-win64 \
      --disable-tests \
      --prefix=/
  )
fi

echo "Building Wine $WINE_VERSION with $jobs jobs..."
(
  cd "$BUILD_DIR"
  run_x86 /usr/bin/env \
    PATH="/usr/local/bin:$build_path" \
    SDKROOT="$sdk_root" \
    MACOSX_DEPLOYMENT_TARGET="$deployment_target" \
    DYLD_FALLBACK_LIBRARY_PATH="$build_dyld_fallback" \
    /usr/bin/make -j "$jobs"
)

staging_parent="$(/usr/bin/mktemp -d "$RUNTIME_SOURCE_DIR/build/runtime-staging.XXXXXX")"
staging_runtime="$staging_parent/$RUNTIME_ROOT"
cleanup_staging() {
  if [[ -d "$staging_parent" ]]; then
    /usr/bin/find "$staging_parent" -depth -delete
  fi
}
trap cleanup_staging EXIT

/usr/bin/tar -xJf "$BASE_ARCHIVE" -C "$staging_parent"
if [[ ! -d "$staging_runtime" ]]; then
  echo "Baseline archive does not contain expected root: $RUNTIME_ROOT" >&2
  exit 1
fi

/usr/bin/printf '%s\n' "$runtime_version" > "$staging_runtime/$RUNTIME_MARKER_FILE"

echo "Installing Wine core into a fresh runtime staging directory..."
(
  cd "$BUILD_DIR"
  run_x86 /usr/bin/env \
    PATH="/usr/local/bin:$build_path" \
    SDKROOT="$sdk_root" \
    MACOSX_DEPLOYMENT_TARGET="$deployment_target" \
    DYLD_FALLBACK_LIBRARY_PATH="$build_dyld_fallback" \
    /usr/bin/make install "DESTDIR=$staging_runtime"
)

# `make install` includes Wine's SDK, developer tools, and unstripped PE
# modules. None are used by Procyon at runtime. Strip the PE builtins and
# retain only the Wine launch/server utilities, keeping the shipped archive
# close to the baseline runtime instead of adding several hundred MB.
strip_tool="$(command -v x86_64-w64-mingw32-strip || true)"
if [[ -z "$strip_tool" ]]; then
  echo "x86_64-w64-mingw32-strip is required to package the runtime." >&2
  exit 1
fi
echo "Stripping Windows modules and removing build-only Wine files..."
/usr/bin/find "$staging_runtime/lib/wine" -type f \
  \( -name '*.dll' -o -name '*.exe' -o -name '*.ocx' -o -name '*.cpl' \
     -o -name '*.drv' -o -name '*.ax' -o -name '*.acm' -o -name '*.vxd' \
     -o -name '*.sys' \) \
  -exec "$strip_tool" --strip-unneeded {} +
if [[ -d "$staging_runtime/include" ]]; then
  /usr/bin/find "$staging_runtime/include" -depth -delete
fi
if [[ -d "$staging_runtime/share/man" ]]; then
  /usr/bin/find "$staging_runtime/share/man" -depth -delete
fi
for build_tool in function_grep.pl winebuild winecpp wineg++ winegcc widl \
  winedump winemaker wmc wrc; do
  if [[ -e "$staging_runtime/bin/$build_tool" ]]; then
    /usr/bin/find "$staging_runtime/bin/$build_tool" -depth -delete
  fi
done

wine_loader="$staging_runtime/lib/wine/x86_64-unix/wine"
wineserver="$staging_runtime/bin/wineserver"
if [[ ! -x "$wine_loader" || ! -x "$wineserver" ]]; then
  echo "Wine install layout is incomplete; expected:" >&2
  echo "  $wine_loader" >&2
  echo "  $wineserver" >&2
  exit 1
fi

if ! /usr/bin/xcrun vtool -show-build "$wine_loader" \
  | /usr/bin/grep -q "minos $deployment_target"; then
  echo "Wine loader deployment target does not match $deployment_target." >&2
  /usr/bin/xcrun vtool -show-build "$wine_loader" >&2
  exit 1
fi

echo "Creating candidate archive: $output_path"
/usr/bin/tar -cJf "$output_path" -C "$staging_parent" "$RUNTIME_ROOT"
candidate_sha="$(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')"
echo "Candidate ready: $output_path"
echo "SHA-256: $candidate_sha"

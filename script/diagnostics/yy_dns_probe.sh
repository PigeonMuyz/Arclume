#!/bin/bash
# Explicit one-session probe. No registry edits or persistent DLL overrides.
set -euo pipefail
case "${1:-}" in --run|--run-software-cef|--run-no-webgl|--run-osr-cpu|--run-osr-software-cef|--run-osr-no-webgl|--run-cef-inspect|--run-in-process-gpu|--self-test) ;; *) echo 'usage: bash script/diagnostics/yy_dns_probe.sh --self-test|--run|--run-software-cef|--run-no-webgl|--run-osr-cpu|--run-osr-software-cef|--run-osr-no-webgl|--run-cef-inspect|--run-in-process-gpu'; exit 2;; esac
if [[ "$1" == --run-cef-inspect ]]; then
    command -v lsof >/dev/null
    if lsof -nP -iTCP:39200-39327 -sTCP:LISTEN >/dev/null; then
        echo 'Inspection ports are occupied; nothing was started.'; exit 3
    fi
    echo 'Explicit inspection: verify loopback listeners before use; test YY closes after 15 minutes.'
fi
probe_root="$(cd "$(dirname "$0")/../.." && pwd)"
probe_support="$HOME/Library/Application Support/Arclume"
probe_runtime="$probe_support/OnlineGameRuntimes/arclume-wine-runtime-x86_64"
probe_graphics_version_source="$probe_runtime/.arclume-d3dmetal-version"
if [[ -n "${ARCLUME_YY_TEST_RUNTIME:-}" ]]; then
    # Explicit one-session runtime selection; never change the installed runtime.
    test "$(tr -d '\r\n' < "$ARCLUME_YY_TEST_RUNTIME/.arclume-yy-lock-test")" = 'builtin-loader-lock-v1'
    probe_runtime="$ARCLUME_YY_TEST_RUNTIME"
    printf 'Using isolated YY loader-lock test runtime: %s\n' "$probe_runtime"
fi
probe_prefix="$probe_support/WindowsGameWinePrefixes/Steam"
probe_dll="$probe_prefix/drive_c/PortableApps/YYSpeak/9.58.0.0/components/com.yy.processservice/197124/gslb.dll"
test -f "$probe_prefix/system.reg" && test -f "$probe_prefix/user.reg"
test -x "$probe_runtime/lib/wine/x86_64-unix/wine"
test "$(shasum -a 256 "$probe_dll" | cut -d ' ' -f 1)" = '5813bd9c8c0b6d7360f9b369e744ab0fac2a0294aa2b10fc43b1927fbe40e108'
if ps -axo comm= | /usr/bin/grep -Ei '(wine(server|device)?|[^/]+\.exe)$' >/dev/null; then
    echo 'Please exit Windows programs before this probe; nothing was stopped.'; exit 3
fi
probe_version="$(tr -d '\r\n' < "$probe_graphics_version_source")"
case "$probe_version" in d3dmetal3) probe_number=3;; d3dmetal4) probe_number=4;; *) exit 4;; esac
probe_archive="$probe_root/DerivedData/Build/Products/Debug/Arclume.app/Contents/Resources/d3dMetal$probe_number.tar.xz"
probe_key="$(stat -f '%z-%m' "$probe_archive")"
probe_graphics="$HOME/Library/Caches/Procyon/BundledOnlineGameResources/d3dMetal$probe_number-$probe_key/d3dMetal$probe_number"
test -f "$probe_graphics/external/libd3dshared.dylib"
probe_output="$(mktemp -d /tmp/arclume-yy-dns-probe.XXXXXX)"
chmod 700 "$probe_output"
x86_64-w64-mingw32-gcc -Wall -Wextra -Werror -O2 -municode "$probe_root/script/diagnostics/yy_dns_probe.c" -o "$probe_output/probe.exe" -lbcrypt -lpsapi
export WINEPREFIX="$probe_prefix" WINEDATADIR="$probe_runtime/share/wine" WINESERVER="$probe_runtime/bin/wineserver"
export WINEDLLPATH="$probe_runtime/lib/wine/x86_64-windows:$probe_runtime/lib/wine/i386-windows:$probe_runtime/lib/wine"
export PROCYON_DLL_PATH="$probe_graphics/wine" CX_APPLEGPTK_LIBD3DSHARED_PATH="$probe_graphics/external/libd3dshared.dylib"
export D3DMETAL_FRAMEWORK_PATH="$probe_graphics/external/D3DMetal.framework/D3DMetal"
export DYLD_FALLBACK_LIBRARY_PATH="$probe_graphics/external:$probe_graphics:$probe_runtime/lib64"
export CX_GRAPHICS_BACKEND=d3dmetal CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal
export D3DM_MTL4="$((probe_number == 4))" D3DM_ENABLE_METALFX=1 DXMT_ENABLE_NVEXT=1
export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1 MVK_CONFIG_LOG_LEVEL=0 WINEMSYNC=1 ROSETTA_ADVERTISE_AVX=1
export PROCYON_NO_GPFAULT_ERROR_DIALOG=1 MTL_HUD_ENABLED=0 __CX_UNIX_MTL_HUD_ENABLED=0
export LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh LC_ALL=zh_CN.UTF-8 LC_CTYPE=zh_CN.UTF-8 LC_MESSAGES=zh_CN.UTF-8
export WINEDEBUG='-all,err+all'
unset WINEDLLOVERRIDES PROCYON_WINE_DOCK_NAME WINEPRELOADERAPPNAME
umask 077
printf 'Probe output: %s\n' "$probe_output"
cd "$probe_prefix/drive_c/PortableApps/YYSpeak"
"$probe_runtime/lib/wine/x86_64-unix/wine" "$probe_output/probe.exe" --self-test > "$probe_output/self-test.log" 2>&1
grep '^YYPROBE' "$probe_output/self-test.log"
if [ "$1" != --self-test ]; then
    "$probe_runtime/lib/wine/x86_64-unix/wine" "$probe_output/probe.exe" "$1" > "$probe_output/session.log" 2>&1
    grep '^YYPROBE' "$probe_output/session.log"
fi

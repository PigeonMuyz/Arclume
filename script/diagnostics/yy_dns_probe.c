/* Opt-in YY 9.58 diagnostic, not a shipping patch engine. No DLL/file writes. */
#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#include <windows.h>
#include <bcrypt.h>
#include <psapi.h>
#include <stdio.h>
#include <wchar.h>
#include <string.h>

static const BYTE before[] = {0xe9,0x4b,0x90,0xff,0xff,0xcc};
/* installHttpDnsResolver(): return -1 (existing failure result), cdecl ret. */
static const BYTE after[] = {0xb8,0xff,0xff,0xff,0xff,0xc3};
static const BYTE digest[32] = {
    0x58,0x13,0xbd,0x9c,0x8c,0x0b,0x6d,0x73,0x60,0xf9,0xb3,0x69,0xe7,0x44,0xab,0x0f,
    0xac,0x2a,0x02,0x94,0xaa,0x2b,0x10,0xfc,0x43,0xb1,0x92,0x7f,0xbe,0x40,0xe1,0x08
};
static const wchar_t target[] = L"C:\\PortableApps\\YYSpeak\\YY.exe";
static const wchar_t dll[] = L"C:\\PortableApps\\YYSpeak\\9.58.0.0\\components\\com.yy.processservice\\197124\\gslb.dll";

static BOOL hash_expected(HANDLE file, LONGLONG expected_size, const BYTE expected_digest[32]) {
    LARGE_INTEGER size, zero = {0};
    BCRYPT_ALG_HANDLE alg = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    BYTE buffer[16384], actual[32];
    DWORD n;
    BOOL ok = FALSE;
    if (!GetFileSizeEx(file, &size) || size.QuadPart != expected_size || !SetFilePointerEx(file, zero, NULL, FILE_BEGIN)) return FALSE;
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL, 0) < 0) goto done;
    if (BCryptCreateHash(alg, &hash, NULL, 0, NULL, 0, 0) < 0) goto done;
    for (;;) {
        if (!ReadFile(file, buffer, sizeof(buffer), &n, NULL)) goto done;
        if (!n) break;
        if (BCryptHashData(hash, buffer, n, 0) < 0) goto done;
    }
    if (BCryptFinishHash(hash, actual, sizeof(actual), 0) >= 0) ok = !memcmp(actual, expected_digest, sizeof(actual));
done:
    if (hash) BCryptDestroyHash(hash);
    if (alg) BCryptCloseAlgorithmProvider(alg, 0);
    return ok;
}

static BOOL hash_matches(HANDLE file) { return hash_expected(file, 291688, digest); }

static BOOL checked_write(HANDLE process, BYTE *address, const BYTE *expected, const BYTE *replacement, SIZE_T length) {
    BYTE bytes[16];
    SIZE_T n;
    DWORD old, ignored;
    if (!length || length > sizeof(bytes)) return FALSE;
    if (!ReadProcessMemory(process, address, bytes, length, &n) || n != length || memcmp(bytes, expected, length)) return FALSE;
    if (!VirtualProtectEx(process, address, length, PAGE_EXECUTE_READWRITE, &old)) return FALSE;
    BOOL ok = WriteProcessMemory(process, address, replacement, length, &n) && n == length;
    if (ok) ok = ReadProcessMemory(process, address, bytes, length, &n) && n == length && !memcmp(bytes, replacement, length);
    if (!ok) WriteProcessMemory(process, address, expected, length, &n);
    BOOL flushed = FlushInstructionCache(process, address, length);
    BOOL protected = VirtualProtectEx(process, address, length, old, &ignored);
    return ok && flushed && protected;
}

static BOOL patch(HANDLE process, BYTE *address) { return checked_write(process, address, before, after, sizeof(before)); }

static const struct {
    const wchar_t *path;
    BYTE sha256[32];
} osr_modules[] = {
    {L"C:\\PortableApps\\YYSpeak\\9.58.0.0\\components\\com.yy.cefdev2\\131387\\yycefdev2.dll",
     {0x9b,0x80,0x20,0x4d,0x57,0x7e,0xaa,0xad,0xfd,0xa1,0x0c,0x12,0xd3,0x67,0xc2,0x25,0x5c,0x98,0x60,0xfb,0x9b,0x7b,0xbc,0xe8,0xf9,0xdd,0xf4,0x1d,0x9a,0x9b,0xe6,0x76}},
    {L"C:\\users\\crossover\\AppData\\Roaming\\duowan\\yy\\yycomstore\\2052\\com.yy.cefdev2\\131389\\yycefdev2.dll",
     {0x7e,0xfd,0x63,0x00,0x50,0x6a,0xcf,0x02,0x9d,0xbf,0x7f,0x68,0xad,0xf9,0x47,0x9e,0x18,0xc5,0xda,0xfa,0xd0,0x8e,0x1a,0x89,0x55,0x28,0xf3,0x09,0x59,0x0b,0x6e,0xc7}}
};

static int osr_module(const wchar_t *path) {
    for (unsigned i = 0; i < sizeof(osr_modules)/sizeof(osr_modules[0]); ++i)
        if (!_wcsicmp(path, osr_modules[i].path)) return (int)i;
    return -1;
}

/* Keep the existing qputenv call and cleanup. Only select its existing "0"
 * string instead of "1" when YY's own config requests GPU OSR. */
static BOOL patch_osr(HANDLE process, BYTE *base) {
    BYTE original[5], replacement[5];
    char key[12], one[2], zero[2]; SIZE_T n;
    DWORD pointer;
    if (!ReadProcessMemory(process, base + 0x2996, original, 5, &n) || n != 5 || original[0] != 0x68) return FALSE;
    memcpy(&pointer, original + 1, 4);
    /* DLL debug notification may be before or after base relocation. */
    if (pointer != 0x10006694 && pointer != (DWORD)((ULONG_PTR)base + 0x6694)) return FALSE;
    if (!ReadProcessMemory(process, base + 0x6688, key, 12, &n) || n != 12 || memcmp(key, "cef_osr_gpu", 12) ||
        !ReadProcessMemory(process, base + 0x6694, one, 2, &n) || n != 2 || memcmp(one, "1", 2) ||
        !ReadProcessMemory(process, base + 0x6648, zero, 2, &n) || n != 2 || memcmp(zero, "0", 2)) return FALSE;
    memcpy(replacement, original, 5);
    pointer -= 0x6694 - 0x6648;
    memcpy(replacement + 1, &pointer, 4);
    return checked_write(process, base + 0x2996, original, replacement, 5);
}

struct unicode32 { USHORT length, capacity; DWORD buffer; };
_Static_assert(sizeof(struct unicode32) == 8, "Wine UNICODE_STRING32 layout");

/* Experimental Wine WOW64 startup override, not a generic libcef binary patch.
 * Only our new, suspended YY 9.58 processes qualify. Never print command lines. */
static BOOL cef_scope(const wchar_t *image) {
    return !_wcsicmp(image, target) ||
        !_wcsicmp(image, L"C:\\PortableApps\\YYSpeak\\9.58.0.0\\YY.exe") ||
        !_wcsicmp(image, L"C:\\PortableApps\\YYSpeak\\9.58.0.0\\yyexternal.exe");
}

static BOOL remote_read(HANDLE process, ULONG_PTR address, void *out, SIZE_T size) {
    SIZE_T n;
    return ReadProcessMemory(process, (void *)address, out, size, &n) && n == size;
}

static const wchar_t *cef_switches(BOOL disable_webgl) {
    return disable_webgl ? L" --disable-gpu --disable-gpu-compositing --disable-webgl" :
        L" --disable-gpu --disable-gpu-compositing";
}

static BOOL cef_arguments(HANDLE process, BOOL disable_webgl) {
    typedef LONG (WINAPI *query_fn)(HANDLE, ULONG, void *, ULONG, ULONG *);
    query_fn query = (query_fn)(void *)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQueryInformationProcess");
    ULONG_PTR peb = 0;
    DWORD params = 0, flags = 0;
    struct unicode32 old, updated, check;
    wchar_t command[16384] = {0};
    const wchar_t *switches = cef_switches(disable_webgl);
    SIZE_T switch_bytes = (wcslen(switches) + 1) * sizeof(wchar_t);
    if (!query || query(process, 26, &peb, sizeof(peb), NULL) < 0 || !peb || peb > 0xfffff000 ||
        !remote_read(process, peb + 0x10, &params, sizeof(params)) || !params || params > 0xfffff000 ||
        !remote_read(process, (ULONG_PTR)params + 8, &flags, sizeof(flags)) || !(flags & 1) ||
        !remote_read(process, (ULONG_PTR)params + 0x40, &old, sizeof(old)) ||
        !old.buffer || old.length % 2 || old.length > old.capacity ||
        old.length + switch_bytes > sizeof(command) ||
        !remote_read(process, old.buffer, command, old.length)) return FALSE;
    if (wcslen(command) * sizeof(wchar_t) != old.length) return FALSE;
    /* Duplicate switches are harmless; fixed switches at the end win. */
    memcpy((BYTE *)command + old.length, switches, switch_bytes);
    SIZE_T size = old.length + switch_bytes, n;
    void *buffer = VirtualAllocEx(process, NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (buffer && (ULONG_PTR)buffer > 0xffffffff - size) {
        VirtualFreeEx(process, buffer, 0, MEM_RELEASE); buffer = NULL;
    }
    for (ULONG_PTR hint = 0x10000000; !buffer && hint < 0x70000000; hint += 0x01000000)
        buffer = VirtualAllocEx(process, (void *)hint, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!buffer) return FALSE;
    updated = (struct unicode32){ .length = (USHORT)(size - 2), .capacity = (USHORT)size, .buffer = (DWORD)(ULONG_PTR)buffer };
    wchar_t verify[16384];
    BOOL ok = WriteProcessMemory(process, buffer, command, size, &n) && n == size &&
        remote_read(process, (ULONG_PTR)buffer, verify, size) && !memcmp(verify, command, size);
    if (ok) {
        ok = WriteProcessMemory(process, (void *)((ULONG_PTR)params + 0x40), &updated, sizeof(updated), &n) && n == sizeof(updated) &&
            remote_read(process, (ULONG_PTR)params + 0x40, &check, sizeof(check)) && !memcmp(&check, &updated, sizeof(check));
        if (!ok) {
            /* Keep the allocation if rollback cannot be confirmed: never leave a dangling pointer. */
            BOOL restored = WriteProcessMemory(process, (void *)((ULONG_PTR)params + 0x40), &old, sizeof(old), &n) && n == sizeof(old) &&
                remote_read(process, (ULONG_PTR)params + 0x40, &check, sizeof(check)) && !memcmp(&check, &old, sizeof(check));
            if (!restored) return FALSE;
        }
    }
    if (!ok) VirtualFreeEx(process, buffer, 0, MEM_RELEASE);
    /* A successful buffer belongs to this process until exit. Do not free the original. */
    return ok;
}

struct tracked { DWORD pid; HANDLE process; BOOL breakpoint, wowbreakpoint, cef_candidate, cef_applied; };
static struct tracked children[128];

/* Only print executable addresses and RTTI type names, never stack contents or exception objects. */
static void print_code_address(HANDLE process, DWORD address) {
    MEMORY_BASIC_INFORMATION info;
    wchar_t path[2048] = {0};
    if (!VirtualQueryEx(process, (void *)(ULONG_PTR)address, &info, sizeof(info)) || info.Type != MEM_IMAGE ||
        !(info.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY))) return;
    if (!GetMappedFileNameW(process, (void *)(ULONG_PTR)address, path, 2048)) return;
    wchar_t *name = wcsrchr(path, L'\\');
    printf("YYPROBE FRAME %ls+%08lx\n", name ? name + 1 : path, address - (DWORD)(ULONG_PTR)info.AllocationBase);
}

static BOOL image_read(HANDLE process, ULONG_PTR address, void *out, SIZE_T size) {
    MEMORY_BASIC_INFORMATION info;
    SIZE_T got;
    if (!VirtualQueryEx(process, (void *)address, &info, sizeof(info)) || info.Type != MEM_IMAGE || info.State != MEM_COMMIT ||
        address + size < address || address + size > (ULONG_PTR)info.BaseAddress + info.RegionSize) return FALSE;
    return ReadProcessMemory(process, (void *)address, out, size, &got) && got == size;
}

static void exception_details(HANDLE process, DWORD threadID, const EXCEPTION_RECORD *exception) {
    SYSTEMTIME time;
    GetLocalTime(&time);
    printf("YYPROBE exception-time %02u:%02u:%02u.%03u\n", time.wHour, time.wMinute, time.wSecond, time.wMilliseconds);
    if (exception->ExceptionCode == 0xe06d7363 && exception->NumberParameters == 3) {
        DWORD throwInfo[4], types[2], catchable[2];
        char type[192] = {0};
        if (image_read(process, exception->ExceptionInformation[2], throwInfo, sizeof(throwInfo)) &&
            image_read(process, throwInfo[3], types, sizeof(types)) && types[0] > 0 && types[0] < 64 &&
            image_read(process, types[1], catchable, sizeof(catchable)) &&
            image_read(process, (ULONG_PTR)catchable[1] + 8, type, sizeof(type) - 1)) {
            BOOL valid = type[0] == '.';
            for (unsigned i = 0; i < sizeof(type) && type[i]; ++i) if ((unsigned char)type[i] < 32 || (unsigned char)type[i] > 126) valid = FALSE;
            if (valid) printf("YYPROBE CXX_TYPE %s\n", type);
        }
    }
    HANDLE thread = OpenThread(THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, threadID);
    WOW64_CONTEXT context = { .ContextFlags = WOW64_CONTEXT_FULL };
    if (thread && Wow64GetThreadContext(thread, &context)) {
        print_code_address(process, context.Eip);
        DWORD frame = context.Ebp;
        for (unsigned i = 0; i < 32 && frame >= context.Esp && frame - context.Esp < 1024 * 1024; ++i) {
            DWORD pair[2]; SIZE_T n;
            if (!ReadProcessMemory(process, (void *)(ULONG_PTR)frame, pair, sizeof(pair), &n) || n != sizeof(pair)) break;
            print_code_address(process, pair[1]);
            if (pair[0] <= frame) break;
            frame = pair[0];
        }
    }
    if (thread) CloseHandle(thread);
}

int wmain(int argc, wchar_t **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc != 2 || (wcscmp(argv[1], L"--run") && wcscmp(argv[1], L"--run-software-cef") &&
        wcscmp(argv[1], L"--run-no-webgl") && wcscmp(argv[1], L"--run-osr-cpu") && wcscmp(argv[1], L"--self-test"))) return 2;
    BOOL osr_cpu = !wcscmp(argv[1], L"--run-osr-cpu");
    BOOL disable_webgl = !wcscmp(argv[1], L"--run-no-webgl");
    BOOL software_cef = disable_webgl || !wcscmp(argv[1], L"--run-software-cef");
    if (!wcscmp(argv[1], L"--self-test")) {
        BYTE *p = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (!p) return 3;
        memcpy(p, before, sizeof(before));
        DWORD old;
        VirtualProtect(p, 4096, PAGE_EXECUTE_READ, &old);
        BOOL ok = patch(GetCurrentProcess(), p) && !memcmp(p, after, sizeof(after));
        ok = ok && !patch(GetCurrentProcess(), p); /* reject mismatched / repeated writes */
        ok = ok && cef_scope(target) && cef_scope(L"C:\\PortableApps\\YYSpeak\\9.58.0.0\\yyexternal.exe") &&
            !cef_scope(L"C:\\Other\\yyexternal.exe") && !cef_scope(L"C:\\PortableApps\\YYSpeak\\10.0\\YY.exe");
        ok = ok && !wcscmp(cef_switches(FALSE), L" --disable-gpu --disable-gpu-compositing") &&
            !wcscmp(cef_switches(TRUE), L" --disable-gpu --disable-gpu-compositing --disable-webgl");
        ok = ok && !cef_arguments(GetCurrentProcess(), FALSE) && !cef_arguments(GetCurrentProcess(), TRUE); /* 64-bit probe is out of scope */
        VirtualFree(p, 0, MEM_RELEASE);
        HANDLE f = CreateFileW(dll, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
        ok = ok && f != INVALID_HANDLE_VALUE && hash_matches(f);
        if (f != INVALID_HANDLE_VALUE) CloseHandle(f);
        BYTE *fixture = VirtualAlloc(NULL, 0x7000, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (!fixture) ok = FALSE;
        else {
            const BYTE instruction[] = {0x68,0x94,0x66,0x00,0x10};
            const BYTE patched_instruction[] = {0x68,0x48,0x66,0x00,0x10};
            memcpy(fixture + 0x2996, instruction, 5);
            memcpy(fixture + 0x6688, "cef_osr_gpu", 12);
            memcpy(fixture + 0x6694, "1", 2); memcpy(fixture + 0x6648, "0", 2);
            ok = ok && patch_osr(GetCurrentProcess(), fixture) && !memcmp(fixture + 0x2996, patched_instruction, 5) &&
                !patch_osr(GetCurrentProcess(), fixture);
            VirtualFree(fixture, 0, MEM_RELEASE);
        }
        ok = ok && osr_module(osr_modules[0].path) == 0 && osr_module(osr_modules[1].path) == 1 && osr_module(L"C:\\Other\\yycefdev2.dll") == -1;
        printf("YYPROBE self-test %s\n", ok ? "PASS" : "FAIL");
        return ok ? 0 : 3;
    }
    HANDLE verified = CreateFileW(dll, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (verified == INVALID_HANDLE_VALUE || !hash_matches(verified)) { puts("YYPROBE REFUSED: DLL SHA256 mismatch"); return 4; }
    if (osr_cpu && !SetEnvironmentVariableW(L"cef_osr_gpu", L"0")) { CloseHandle(verified); return 4; }
    printf("YYPROBE mode software_cef=%d disable_webgl=%d osr_cpu=%d\n", software_cef, disable_webgl, osr_cpu);
    /* Hold a read-only sharing handle until the complete debug tree exits. */
    STARTUPINFOW startup = { .cb = sizeof(startup) };
    PROCESS_INFORMATION pi = {0};
    wchar_t command[] = L"\"C:\\PortableApps\\YYSpeak\\YY.exe\"";
    if (!CreateProcessW(target, command, NULL, NULL, FALSE, DEBUG_PROCESS, NULL, L"C:\\PortableApps\\YYSpeak", &startup, &pi)) {
        printf("YYPROBE launch failed %lu\n", GetLastError()); CloseHandle(verified); return 5;
    }
    DebugSetProcessKillOnExit(FALSE);
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
    unsigned live = 0, patched = 0;
    BOOL failed = FALSE;
    for (;;) {
        DEBUG_EVENT event;
        if (!WaitForDebugEvent(&event, 1000)) {
            if (GetLastError() == ERROR_SEM_TIMEOUT) continue;
            printf("YYPROBE debug wait failed %lu\n", GetLastError()); failed = TRUE; break;
        }
        struct tracked *child = NULL;
        for (unsigned i = 0; i < 128; ++i) if (children[i].pid == event.dwProcessId) child = &children[i];
        DWORD status = DBG_CONTINUE;
        if (event.dwDebugEventCode == CREATE_PROCESS_DEBUG_EVENT) {
            for (unsigned i = 0; i < 128 && !child; ++i) if (!children[i].pid) child = &children[i];
            if (!child) { failed = TRUE; }
            else { *child = (struct tracked){ .pid = event.dwProcessId, .process = event.u.CreateProcessInfo.hProcess }; ++live; }
            if (child && software_cef && event.u.CreateProcessInfo.hFile) {
                wchar_t path[2048] = {0};
                DWORD len = GetFinalPathNameByHandleW(event.u.CreateProcessInfo.hFile, path, 2048, FILE_NAME_NORMALIZED);
                const wchar_t *name = !wcsncmp(path, L"\\\\?\\", 4) ? path + 4 : path;
                child->cef_candidate = len && len < 2048 && cef_scope(name);
                if (child->cef_candidate) {
                    child->cef_applied = cef_arguments(child->process, disable_webgl);
                    printf("YYPROBE CEF_ARGS_%s pid=%lu stage=create\n", child->cef_applied ? "APPLIED" : "PENDING", child->pid);
                }
            }
            if (event.u.CreateProcessInfo.hFile) CloseHandle(event.u.CreateProcessInfo.hFile);
            printf("YYPROBE child pid=%lu\n", event.dwProcessId);
        } else if (event.dwDebugEventCode == LOAD_DLL_DEBUG_EVENT) {
            HANDLE file = event.u.LoadDll.hFile;
            wchar_t path[2048] = {0};
            DWORD len = file ? GetFinalPathNameByHandleW(file, path, 2048, FILE_NAME_NORMALIZED) : 0;
            const wchar_t *name = !wcsncmp(path, L"\\\\?\\", 4) ? path + 4 : path;
            if (len && len < 2048 && !_wcsicmp(name, dll)) {
                BOOL ok = child && hash_matches(file) && patch(child->process, (BYTE *)event.u.LoadDll.lpBaseOfDll + 0x20050);
                printf("YYPROBE %s pid=%lu base=%p rva=00020050\n", ok ? "PATCHED" : "REFUSED", event.dwProcessId, event.u.LoadDll.lpBaseOfDll);
                if (ok) ++patched; else failed = TRUE;
            }
            int osr_index = len && len < 2048 ? osr_module(name) : -1;
            if (osr_cpu && osr_index >= 0) {
                BOOL ok = child && hash_expected(file, 48800, osr_modules[osr_index].sha256) &&
                    patch_osr(child->process, (BYTE *)event.u.LoadDll.lpBaseOfDll);
                printf("YYPROBE OSR_CPU_%s pid=%lu component=%d rva=00002996\n", ok ? "PATCHED" : "REFUSED", event.dwProcessId, osr_index);
                if (!ok) failed = TRUE;
            }
            if (file) CloseHandle(file);
        } else if (event.dwDebugEventCode == EXCEPTION_DEBUG_EVENT) {
            DWORD code = event.u.Exception.ExceptionRecord.ExceptionCode;
            status = DBG_EXCEPTION_NOT_HANDLED;
            if (child && event.u.Exception.dwFirstChance && code == EXCEPTION_BREAKPOINT && !child->breakpoint) { child->breakpoint = TRUE; status = DBG_CONTINUE; }
            if (child && event.u.Exception.dwFirstChance && code == 0x4000001f && !child->wowbreakpoint) { child->wowbreakpoint = TRUE; status = DBG_CONTINUE; }
            if (child && child->cef_candidate && !child->cef_applied && status == DBG_CONTINUE) {
                child->cef_applied = cef_arguments(child->process, disable_webgl);
                printf("YYPROBE CEF_ARGS_%s pid=%lu stage=breakpoint\n", child->cef_applied ? "APPLIED" : "REFUSED", child->pid);
            }
            if (!event.u.Exception.dwFirstChance) {
                printf("YYPROBE UNHANDLED pid=%lu code=%08lx address=%p\n", event.dwProcessId, code, event.u.Exception.ExceptionRecord.ExceptionAddress);
                if (child) exception_details(child->process, event.dwThreadId, &event.u.Exception.ExceptionRecord);
            }
        } else if (event.dwDebugEventCode == EXIT_PROCESS_DEBUG_EVENT) {
            printf("YYPROBE exit pid=%lu code=%08lx\n", event.dwProcessId, event.u.ExitProcess.dwExitCode);
            if (child) { memset(child, 0, sizeof(*child)); --live; }
        }
        if (!ContinueDebugEvent(event.dwProcessId, event.dwThreadId, status)) { failed = TRUE; break; }
        if (!live) break;
    }
    for (unsigned i = 0; i < 128; ++i) if (children[i].pid) DebugActiveProcessStop(children[i].pid);
    CloseHandle(verified);
    printf("YYPROBE complete patches=%u failed=%d\n", patched, failed);
    return failed || !patched ? 6 : 0;
}

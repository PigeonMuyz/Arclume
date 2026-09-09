#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include <tlhelp32.h>
#include <psapi.h>

static BOOL scoped(HANDLE p) {
    wchar_t path[2048]; DWORD n = 2048;
    if (!QueryFullProcessImageNameW(p, 0, path, &n)) return FALSE;
    for (DWORD i=0; i<n; ++i) if (path[i]==L'/') path[i]=L'\\';
    if (!_wcsnicmp(path,L"C:\\PortableApps\\YYSpeak\\",24)) return TRUE;
    /* This downloaded YY login component runs outside the install directory. */
    wchar_t appdata[2048], login[2048];
    DWORD len = GetEnvironmentVariableW(L"APPDATA", appdata, 2048);
    if (!len || len >= 2048) return FALSE;
    int written = swprintf(login, 2048, L"%ls\\duowan\\yy\\yycomstore\\2052\\com.yy.webrunlogin\\131082\\yyqlogin.exe", appdata);
    return written > 0 && written < 2048 && !_wcsicmp(path, login);
}
static void command_state(HANDLE p, DWORD pid) {
    typedef LONG (WINAPI *query_fn)(HANDLE,ULONG,void*,ULONG,ULONG*);
    query_fn q=(query_fn)(void*)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"NtQueryInformationProcess");
    ULONG_PTR peb=0; DWORD params=0; SIZE_T n;
    struct { USHORT len,cap; DWORD ptr; } u;
    wchar_t cmd[16384]={0};
    if(q && q(p,26,&peb,sizeof(peb),NULL)>=0 && peb &&
       ReadProcessMemory(p,(void*)(peb+0x10),&params,4,&n) && n==4 &&
       ReadProcessMemory(p,(void*)((ULONG_PTR)params+0x40),&u,8,&n) && n==8 && u.len<sizeof(cmd) && u.len%2==0 &&
       ReadProcessMemory(p,(void*)(ULONG_PTR)u.ptr,cmd,u.len,&n) && n==u.len)
        printf("YYARGS pid=%lu disable_gpu=%d disable_compositing=%d disable_webgl=%d in_process_gpu=%d gpu_child=%d renderer_child=%d\n",pid,wcsstr(cmd,L"--disable-gpu")!=NULL,wcsstr(cmd,L"--disable-gpu-compositing")!=NULL,wcsstr(cmd,L"--disable-webgl")!=NULL,wcsstr(cmd,L"--in-process-gpu")!=NULL,wcsstr(cmd,L"--type=gpu-process")!=NULL,wcsstr(cmd,L"--type=renderer")!=NULL);
    DWORD environment=0;
    if(params && ReadProcessMemory(p,(void*)((ULONG_PTR)params+0x48),&environment,4,&n) && n==4 && environment) {
        wchar_t entry[2048]; unsigned used=0; BOOL found=FALSE;
        for(unsigned i=0;i<65536;++i) {
            wchar_t ch;
            if(!ReadProcessMemory(p,(void*)((ULONG_PTR)environment+i*2),&ch,2,&n)||n!=2) break;
            if(used>=2047) break;
            entry[used++]=ch;
            if(!ch) {
                if(used==1) break;
                if(!_wcsnicmp(entry,L"cef_osr_gpu=",12)) {
                    printf("YYENV pid=%lu cef_osr_gpu=%s\n",pid,!wcscmp(entry+12,L"1")?"1":!wcscmp(entry+12,L"0")?"0":"other"); found=TRUE;
                }
                used=0;
            }
        }
        if(!found) printf("YYENV pid=%lu cef_osr_gpu=not-found\n",pid);
    }
}
static BOOL CALLBACK window(HWND hwnd, LPARAM unused);
static BOOL include_small_windows;
static void address(HANDLE p, DWORD pc) {
    MEMORY_BASIC_INFORMATION m; wchar_t path[2048];
    if (!VirtualQueryEx(p,(void *)(ULONG_PTR)pc,&m,sizeof(m)) || m.Type!=MEM_IMAGE ||
        !(m.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) ||
        !GetMappedFileNameW(p,(void *)(ULONG_PTR)pc,path,2048)) return;
    wchar_t *base=wcsrchr(path,L'\\');
    printf(" %ls+%lx",base?base+1:path,pc-(DWORD)(ULONG_PTR)m.AllocationBase);
}
static void stacks(void) {
    HANDLE s=CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD,0);
    THREADENTRY32 e={.dwSize=sizeof(e)};
    if(s==INVALID_HANDLE_VALUE) return;
    if(Thread32First(s,&e)) do {
        HANDLE p=OpenProcess(PROCESS_QUERY_INFORMATION|PROCESS_VM_READ,FALSE,e.th32OwnerProcessID);
        if(!p) continue;
        if(scoped(p)) {
            if(e.th32ThreadID==e.th32OwnerProcessID+4) command_state(p,e.th32OwnerProcessID);
            EnumThreadWindows(e.th32ThreadID,window,0);
            HANDLE t=OpenThread(THREAD_GET_CONTEXT|THREAD_SUSPEND_RESUME,FALSE,e.th32ThreadID);
            if(t && SuspendThread(t)!=0xffffffff) {
                WOW64_CONTEXT c={.ContextFlags=WOW64_CONTEXT_FULL};
                BOOL ok=Wow64GetThreadContext(t,&c);
                /* Take just context while paused; always immediately balance suspend. */
                ResumeThread(t);
                if(ok) {
                    printf("YYSTACK pid=%lu tid=%lu",e.th32OwnerProcessID,e.th32ThreadID);
                    address(p,c.Eip);
                    DWORD fp=c.Ebp;
                    for(unsigned j=0;j<12 && fp>=c.Esp && fp-c.Esp<1048576;++j) {
                        DWORD pair[2]; SIZE_T got;
                        if(!ReadProcessMemory(p,(void *)(ULONG_PTR)fp,pair,sizeof(pair),&got)||got!=sizeof(pair)) break;
                        address(p,pair[1]); if(pair[0]<=fp) break; fp=pair[0];
                    }
                    puts("");
                }
            }
            if(t) CloseHandle(t);
        }
        CloseHandle(p);
    }while(Thread32Next(s,&e));
    CloseHandle(s);
}

static BOOL CALLBACK window(HWND hwnd, LPARAM unused) {
    (void)unused;
    RECT bounds={0}; GetWindowRect(hwnd,&bounds);
    if(!include_small_windows && (bounds.right-bounds.left<400 || bounds.bottom-bounds.top<200)) return TRUE;
    if(include_small_windows && !IsWindowVisible(hwnd)) return TRUE;
    DWORD pid = 0;
    DWORD tid = GetWindowThreadProcessId(hwnd, &pid);
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    wchar_t cls[128];
    BOOL match = p && scoped(p);
    if (p) CloseHandle(p);
    if (!match) {
        if (include_small_windows) return TRUE;
        RECT other = {0}; GetWindowRect(hwnd, &other);
        printf("OTHERWINDOW pid=%lu tid=%lu size=%ldx%ld\n", pid, tid, other.right-other.left, other.bottom-other.top);
        return TRUE;
    }
    cls[0] = 0; GetClassNameW(hwnd, cls, 128);
    DWORD_PTR result;
    BOOL responsive = SendMessageTimeoutW(hwnd, WM_NULL, 0, 0, SMTO_ABORTIFHUNG | SMTO_BLOCK, 250, &result) != 0;
    RECT r = {0}; GetWindowRect(hwnd, &r);
    BYTE alpha=0; DWORD layer_flags=0; COLORREF color=0;
    BOOL layer=GetLayeredWindowAttributes(hwnd,&color,&alpha,&layer_flags);
    printf("YYWINDOW hwnd=%p parent=%p owner=%p pid=%lu tid=%lu class=%ls rect=%ld,%ld,%ld,%ld responsive=%d visible=%d enabled=%d style=%08lx exstyle=%08lx layered=%d alpha=%u layerflags=%lu\n",
        hwnd,GetParent(hwnd),GetWindow(hwnd,GW_OWNER),pid,tid,cls,r.left,r.top,r.right,r.bottom,responsive,
        IsWindowVisible(hwnd),IsWindowEnabled(hwnd),(DWORD)GetWindowLongW(hwnd,GWL_STYLE),(DWORD)GetWindowLongW(hwnd,GWL_EXSTYLE),layer,alpha,layer_flags);
    return TRUE;
}
static BOOL CALLBACK tree(HWND hwnd, LPARAM unused) { window(hwnd,unused); EnumChildWindows(hwnd,window,0); return TRUE; }
/* Read a sparse pixel grid, not window text or a screenshot. GetPixel does not
 * necessarily see D3D surfaces; invalid/flat pixels alone are not proof of failure. */
static BOOL CALLBACK pixels(HWND hwnd, LPARAM unused) {
    (void)unused;
    DWORD pid = 0; GetWindowThreadProcessId(hwnd, &pid);
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    BOOL match = p && scoped(p);
    if (p) CloseHandle(p);
    RECT r; GetClientRect(hwnd, &r);
    if (!match || !IsWindowVisible(hwnd) || r.right < 800 || r.bottom < 500) return TRUE;
    HDC dc = GetDC(hwnd);
    if (!dc) return TRUE;
    RECT clip={0}; int clip_type=GetClipBox(dc,&clip);
    unsigned valid = 0, light = 0, dark = 0, colored = 0;
    for (int y = 1; y < 7; ++y) for (int x = 1; x < 9; ++x) {
        COLORREF color = GetPixel(dc, r.right * x / 9, r.bottom * y / 7);
        if (color == CLR_INVALID) continue;
        ++valid;
        unsigned red = GetRValue(color), green = GetGValue(color), blue = GetBValue(color);
        if (red > 225 && green > 225 && blue > 225) ++light;
        if (red < 70 && green < 70 && blue < 70) ++dark;
        if (abs((int)red - (int)green) > 30 || abs((int)green - (int)blue) > 30) ++colored;
    }
    ReleaseDC(hwnd, dc);
    wchar_t cls[128] = {0}; GetClassNameW(hwnd, cls, 128);
    printf("YYPIXELS hwnd=%p class=%ls cliptype=%d clip=%ld,%ld,%ld,%ld valid=%u light=%u dark=%u colored=%u total=48\n", hwnd, cls, clip_type,clip.left,clip.top,clip.right,clip.bottom,valid, light, dark, colored);
    return TRUE;
}
static BOOL CALLBACK pixel_tree(HWND hwnd, LPARAM unused) { pixels(hwnd,unused); EnumChildWindows(hwnd,pixels,0); return TRUE; }
static BOOL CALLBACK input_window(HWND hwnd, LPARAM unused) {
    (void)unused;
    DWORD pid = 0, tid = GetWindowThreadProcessId(hwnd, &pid);
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    BOOL match = p && scoped(p);
    if (p) CloseHandle(p);
    if (!match || !IsWindowVisible(hwnd)) return TRUE;
    GUITHREADINFO info = {.cbSize = sizeof(info)};
    RECT r = {0}; GetWindowRect(hwnd, &r);
    wchar_t cls[128] = {0}; GetClassNameW(hwnd, cls, 128);
    BOOL ok = GetGUIThreadInfo(tid, &info);
    POINT center = {(r.left + r.right) / 2, (r.top + r.bottom) / 2};
    POINT caption = {r.right - 35, r.top + 20};
    printf("YYINPUT pid=%lu tid=%lu hwnd=%p class=%ls rect=%ld,%ld,%ld,%ld enabled=%d gui=%d flags=%lx active=%p focus=%p capture=%p menu=%p move=%p center_hit=%p caption_hit=%p\n",
        pid,tid,hwnd,cls,r.left,r.top,r.right,r.bottom,IsWindowEnabled(hwnd),ok,info.flags,
        info.hwndActive,info.hwndFocus,info.hwndCapture,info.hwndMenuOwner,info.hwndMoveSize,
        WindowFromPoint(center),WindowFromPoint(caption));
    return TRUE;
}
/* One reversible experiment: only the disabled, layered QTool shadow around a
 * visible YY channel. Never reparent windows or touch the actual browser view. */
static BOOL shadow_matches(HWND hwnd, HWND *owner_out, DWORD *pid_out) {
    wchar_t cls[128] = {0};
    GetClassNameW(hwnd, cls, 128);
    if (wcscmp(cls, L"QTool") || !IsWindowVisible(hwnd) || IsWindowEnabled(hwnd)) return FALSE;
    DWORD ex = GetWindowLongW(hwnd, GWL_EXSTYLE);
    if ((ex & (WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT)) !=
        (WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT)) return FALSE;
    HWND owner = GetWindow(hwnd, GW_OWNER);
    if (!owner || !IsWindowVisible(owner)) return FALSE;
    GetClassNameW(owner, cls, 128);
    if (wcscmp(cls, L"QWidget") || !FindWindowExW(owner, NULL, L"YYCefWindow", NULL)) return FALSE;
    DWORD pid = 0, owner_pid = 0;
    GetWindowThreadProcessId(hwnd, &pid); GetWindowThreadProcessId(owner, &owner_pid);
    if (!pid || pid != owner_pid) return FALSE;
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    BOOL match = p && scoped(p);
    if (p) CloseHandle(p);
    if (!match) return FALSE;
    RECT r, o;
    if (!GetWindowRect(hwnd, &r) || !GetWindowRect(owner, &o) || o.right-o.left < 800 || o.bottom-o.top < 500) return FALSE;
    if (o.left-r.left != 30 || o.top-r.top != 30 || r.right-o.right != 30 || r.bottom-o.bottom != 30) return FALSE;
    *owner_out = owner; *pid_out = pid; return TRUE;
}
struct shadow_target { HWND hwnd, owner; DWORD pid; unsigned count; };
static BOOL CALLBACK shadow_candidate(HWND hwnd, LPARAM data) {
    struct shadow_target *target = (struct shadow_target *)data;
    HWND owner; DWORD pid;
    if (shadow_matches(hwnd, &owner, &pid)) {
        target->hwnd=hwnd; target->owner=owner; target->pid=pid; ++target->count;
    }
    return TRUE;
}
static int shadow_probe(BOOL hide) {
    struct shadow_target t = {0};
    EnumWindows(shadow_candidate, (LPARAM)&t);
    printf("YYSHADOW matches=%u\n", t.count);
    if (t.count != 1) return 2;
    printf("YYSHADOW hwnd=%p owner=%p pid=%lu\n", t.hwnd, t.owner, t.pid);
    if (!hide) return 0;
    if (!ShowWindowAsync(t.hwnd, SW_HIDE)) return 3;
    for (unsigned i=0; i<25 && IsWindowVisible(t.hwnd); ++i) Sleep(40);
    printf("YYSHADOW hidden=%d\n",!IsWindowVisible(t.hwnd));
    puts("YYSHADOW hide requested; restore in 30 seconds"); fflush(stdout);
    Sleep(30000);
    DWORD pid=0; GetWindowThreadProcessId(t.hwnd, &pid);
    wchar_t cls[128]={0}; GetClassNameW(t.hwnd,cls,128);
    if (pid == t.pid && GetWindow(t.hwnd,GW_OWNER) == t.owner && IsWindowVisible(t.owner) && !wcscmp(cls,L"QTool")) {
        BOOL restored = ShowWindowAsync(t.hwnd, SW_SHOWNOACTIVATE);
        for (unsigned i=0; i<25 && !IsWindowVisible(t.hwnd); ++i) Sleep(40);
        printf("YYSHADOW restore requested=%d visible=%d\n",restored,IsWindowVisible(t.hwnd)); return restored ? 0 : 4;
    }
    puts("YYSHADOW original window closed or replaced; nothing restored"); return 0;
}
static BOOL CALLBACK channel_candidate(HWND hwnd, LPARAM data) {
    struct shadow_target *t=(struct shadow_target *)data;
    wchar_t cls[128]={0}; GetClassNameW(hwnd,cls,128);
    RECT r; GetClientRect(hwnd,&r);
    if (wcscmp(cls,L"QWidget") || !IsWindowVisible(hwnd) || !IsWindowEnabled(hwnd) || r.right<800 || r.bottom<500 ||
        !FindWindowExW(hwnd,NULL,L"YYCefWindow",NULL)) return TRUE;
    DWORD pid=0; GetWindowThreadProcessId(hwnd,&pid);
    HANDLE p=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);
    BOOL match=p && scoped(p); if(p) CloseHandle(p);
    if(match) { t->hwnd=hwnd; t->pid=pid; ++t->count; }
    return TRUE;
}
static int repaint_channel(void) {
    struct shadow_target t={0}; EnumWindows(channel_candidate,(LPARAM)&t);
    printf("YYREPAINT matches=%u\n",t.count);
    if(t.count!=1) return 2;
    /* Queue paint, do not synchronously enter a possibly blocked window thread. */
    BOOL ok=RedrawWindow(t.hwnd,NULL,NULL,RDW_INVALIDATE|RDW_FRAME|RDW_ALLCHILDREN);
    printf("YYREPAINT hwnd=%p queued=%d\n",t.hwnd,ok); return ok?0:3;
}
int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if(argc==2 && !strcmp(argv[1],"--shadow-preview")) return shadow_probe(FALSE);
    if(argc==2 && !strcmp(argv[1],"--shadow-hide")) return shadow_probe(TRUE);
    if(argc==2 && !strcmp(argv[1],"--repaint-channel")) return repaint_channel();
    if(argc==2 && !strcmp(argv[1],"--pixels")) { EnumWindows(pixel_tree,0); return 0; }
    if(argc==2 && !strcmp(argv[1],"--input")) { EnumWindows(input_window,0); return 0; }
    if(argc==2 && !strcmp(argv[1],"--windows")) { EnumWindows(tree,0); return 0; }
    if(argc==2 && !strcmp(argv[1],"--all-visible-windows")) { include_small_windows=TRUE; EnumWindows(tree,0); return 0; }
    if(argc>1) { EnumWindows(window, 0); stacks(); return 0; }
    HANDLE s=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
    PROCESSENTRY32 e={.dwSize=sizeof(e)};
    if(s==INVALID_HANDLE_VALUE) return 1;
    if(Process32First(s,&e)) do {
        HANDLE p=OpenProcess(PROCESS_QUERY_INFORMATION|PROCESS_VM_READ,FALSE,e.th32ProcessID);
        if(p) { if(scoped(p)) command_state(p,e.th32ProcessID); CloseHandle(p); }
    }while(Process32Next(s,&e));
    CloseHandle(s); return 0;
}

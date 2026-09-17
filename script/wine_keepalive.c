/* Arclume GPL helper: keep only this Wine client alive while the host pipe is open. */
#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#include <windows.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command, int show) {
    (void)instance; (void)previous; (void)command; (void)show;
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD count;
    const char ready[] = "ARCLUME_WINE_READY\n";
    if (GetFileType(input) != FILE_TYPE_PIPE) return 2;
    if (!WriteFile(output, ready, sizeof(ready) - 1, &count, NULL)) return 3;
    char byte;
    while (ReadFile(input, &byte, 1, &count, NULL) && count) { }
    return 0;
}

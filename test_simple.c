// Minimal mIRC DLL test
#include <windows.h>
#include <stdio.h>

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved)
{
    return TRUE;
}

__declspec(dllexport)
int __stdcall TestSimple(HWND mWnd, HWND aWnd, char *data, char *parms, BOOL *show, BOOL *nopause)
{
    strcpy(data, "SIMPLE TEST OK");
    return 3;
}

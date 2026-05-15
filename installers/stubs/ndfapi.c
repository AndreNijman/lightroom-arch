#include <windows.h>

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpReserved) {
    return TRUE;
}

__declspec(dllexport) HRESULT WINAPI NdfCloseIncident(HANDLE handle) {
    return S_OK;
}

__declspec(dllexport) HRESULT WINAPI NdfCreateWebIncident(LPCWSTR url, HANDLE *out) {
    if (out) *out = NULL;
    return E_NOTIMPL;
}

__declspec(dllexport) HRESULT WINAPI NdfExecuteDiagnosis(HANDLE handle, HWND hwnd) {
    return E_NOTIMPL;
}

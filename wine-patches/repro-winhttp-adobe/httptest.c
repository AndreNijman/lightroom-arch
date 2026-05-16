/* httptest.c - minimal Wine winhttp HTTPS probe.
 * Usage: httptest.exe <host> <path> [threads]
 * One winhttp GET per thread; prints each thread's HTTP status or the
 * failing WinHTTP call + error. Used to repro Wine winhttp/secur32 behaviour
 * (in particular concurrent-handshake races) without any Adobe software. */
#include <windows.h>
#include <winhttp.h>
#include <stdio.h>

static const wchar_t *g_host, *g_path;

static DWORD WINAPI worker(void *arg)
{
    int id = (int)(INT_PTR)arg;
    HINTERNET ses = WinHttpOpen(L"httptest/1.0", WINHTTP_ACCESS_TYPE_NO_PROXY,
                                WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!ses) { printf("[%d] WinHttpOpen err=%lu\n", id, GetLastError()); return 1; }
    HINTERNET con = WinHttpConnect(ses, g_host, INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!con) { printf("[%d] WinHttpConnect err=%lu\n", id, GetLastError()); return 2; }
    HINTERNET req = WinHttpOpenRequest(con, L"GET", g_path, NULL, WINHTTP_NO_REFERER,
                                       WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!req) { printf("[%d] WinHttpOpenRequest err=%lu\n", id, GetLastError()); return 3; }
    if (!WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
        printf("[%d] WinHttpSendRequest err=%lu\n", id, GetLastError()); return 4;
    }
    if (!WinHttpReceiveResponse(req, NULL)) {
        printf("[%d] WinHttpReceiveResponse err=%lu\n", id, GetLastError()); return 5;
    }
    DWORD status = 0, sz = sizeof(status);
    WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &status, &sz, WINHTTP_NO_HEADER_INDEX);
    printf("[%d] OK HTTP status=%lu\n", id, status);
    return 0;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc < 3) { printf("usage: httptest <host> <path> [threads]\n"); return 99; }
    g_host = argv[1]; g_path = argv[2];
    int n = (argc > 3) ? _wtoi(argv[3]) : 1;
    if (n < 1) n = 1;
    HANDLE th[64];
    if (n > 64) n = 64;
    for (int i = 0; i < n; i++)
        th[i] = CreateThread(NULL, 0, worker, (void *)(INT_PTR)i, 0, NULL);
    WaitForMultipleObjects(n, th, TRUE, INFINITE);
    return 0;
}

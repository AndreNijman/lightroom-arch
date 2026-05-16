/* httptest-async.c - minimal Wine winhttp HTTPS async probe.
 * Usage: httptest-async.exe <host> <path> [threads]
 * One ASYNC winhttp GET per thread on a shared session; prints each request's
 * HTTP status or error via callback. Used to repro Wine winhttp async behaviour
 * without any Adobe software. */
#include <windows.h>
#include <winhttp.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int id;
    HINTERNET req;
    HANDLE done;
    DWORD http_status;
    DWORD error_code;
    BOOL success;
} REQUEST_STATE;

static const wchar_t *g_host, *g_path;
static HINTERNET g_session, g_connect;

/* Callback for async notifications */
static VOID CALLBACK async_callback(
    HINTERNET hInternet,
    DWORD_PTR dwContext,
    DWORD dwInternetStatus,
    LPVOID lpvStatusInformation,
    DWORD dwStatusInformationLength)
{
    REQUEST_STATE *state = (REQUEST_STATE *)dwContext;
    
    (void)hInternet;
    (void)dwStatusInformationLength;
    
    switch (dwInternetStatus) {
        case WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE:
            /* Request sent, now receive response */
            if (!WinHttpReceiveResponse(state->req, NULL)) {
                DWORD err = GetLastError();
                printf("[%d] WinHttpReceiveResponse err=%lu\n", state->id, err);
                state->error_code = err;
                SetEvent(state->done);
            }
            break;
            
        case WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE: {
            /* Headers received, query status code */
            DWORD status = 0, sz = sizeof(status);
            if (!WinHttpQueryHeaders(state->req,
                                      WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                                      WINHTTP_HEADER_NAME_BY_INDEX, &status, &sz,
                                      WINHTTP_NO_HEADER_INDEX)) {
                DWORD err = GetLastError();
                printf("[%d] WinHttpQueryHeaders err=%lu\n", state->id, err);
                state->error_code = err;
            } else {
                state->http_status = status;
                state->success = TRUE;
            }
            SetEvent(state->done);
            break;
        }
        
        case WINHTTP_CALLBACK_STATUS_REQUEST_ERROR: {
            /* Async error occurred */
            WINHTTP_ASYNC_RESULT *pAsyncResult = (WINHTTP_ASYNC_RESULT *)lpvStatusInformation;
            if (pAsyncResult) {
                printf("[%d] ASYNC ERROR result=%llu error=%llu\n", state->id,
                       (unsigned long long)pAsyncResult->dwResult,
                       (unsigned long long)pAsyncResult->dwError);
                state->error_code = pAsyncResult->dwError;
            }
            SetEvent(state->done);
            break;
        }
        
        case WINHTTP_CALLBACK_STATUS_SECURE_FAILURE: {
            /* SSL/TLS error */
            DWORD dwFlags = *(DWORD *)lpvStatusInformation;
            printf("[%d] SECURE_FAILURE flags=0x%lx\n", state->id, dwFlags);
            break;
        }
    }
}

static DWORD launch_async_request(REQUEST_STATE *state)
{
    state->done = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!state->done) {
        printf("[%d] CreateEvent err=%lu\n", state->id, GetLastError());
        return 1;
    }
    
    /* Create request handle on the shared connect handle */
    state->req = WinHttpOpenRequest(g_connect, L"GET", g_path, NULL,
                                    WINHTTP_NO_REFERER,
                                    WINHTTP_DEFAULT_ACCEPT_TYPES,
                                    WINHTTP_FLAG_SECURE);
    if (!state->req) {
        printf("[%d] WinHttpOpenRequest err=%lu\n", state->id, GetLastError());
        return 2;
    }
    
    /* Set callback for all notifications */
    if (WinHttpSetStatusCallback(state->req, async_callback,
                                 WINHTTP_CALLBACK_FLAG_ALL_NOTIFICATIONS,
                                 0) == WINHTTP_INVALID_STATUS_CALLBACK) {
        printf("[%d] WinHttpSetStatusCallback err=%lu\n", state->id, GetLastError());
        return 3;
    }
    
    /* Send request asynchronously (returns immediately) */
    if (!WinHttpSendRequest(state->req, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, (DWORD_PTR)state)) {
        printf("[%d] WinHttpSendRequest err=%lu\n", state->id, GetLastError());
        return 4;
    }
    
    return 0;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc < 3) {
        printf("usage: httptest-async <host> <path> [threads]\n");
        return 99;
    }
    
    g_host = argv[1];
    g_path = argv[2];
    int n = (argc > 3) ? _wtoi(argv[3]) : 1;
    if (n < 1) n = 1;
    if (n > 64) n = 64;
    
    /* Open async session (shared across all requests) */
    g_session = WinHttpOpen(L"httptest-async/1.0", WINHTTP_ACCESS_TYPE_NO_PROXY,
                            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS,
                            WINHTTP_FLAG_ASYNC);
    if (!g_session) {
        printf("WinHttpOpen err=%lu\n", GetLastError());
        return 1;
    }
    
    /* Connect once (reused for all requests) */
    g_connect = WinHttpConnect(g_session, g_host, INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!g_connect) {
        printf("WinHttpConnect err=%lu\n", GetLastError());
        WinHttpCloseHandle(g_session);
        return 2;
    }
    
    /* Launch all async requests */
    REQUEST_STATE states[64];
    for (int i = 0; i < n; i++) {
        states[i].id = i;
        states[i].req = NULL;
        states[i].done = NULL;
        states[i].http_status = 0;
        states[i].error_code = 0;
        states[i].success = FALSE;
        
        if (launch_async_request(&states[i])) {
            return 5;
        }
    }
    
    /* Wait for all requests with 40s timeout total */
    DWORD start = GetTickCount();
    DWORD timeout_ms = 40000;
    
    for (int i = 0; i < n; i++) {
        DWORD elapsed = GetTickCount() - start;
        DWORD remaining = (elapsed >= timeout_ms) ? 0 : (timeout_ms - elapsed);
        
        DWORD wait_result = WaitForSingleObject(states[i].done, remaining);
        if (wait_result == WAIT_TIMEOUT) {
            printf("[%d] TIMEOUT\n", states[i].id);
        } else if (states[i].success) {
            printf("[%d] OK HTTP status=%lu\n", states[i].id, states[i].http_status);
        } else if (states[i].error_code) {
            printf("[%d] ERROR code=%lu\n", states[i].id, states[i].error_code);
        }
        
        /* Cleanup */
        if (states[i].req) WinHttpCloseHandle(states[i].req);
        if (states[i].done) CloseHandle(states[i].done);
    }
    
    /* Cleanup */
    WinHttpCloseHandle(g_connect);
    WinHttpCloseHandle(g_session);
    
    return 0;
}

#include <windows.h>
#include <ole2.h>
#include <exdisp.h>
#include <mshtml.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Minimal IOleClientSite implementation */
typedef struct {
    IOleClientSiteVtbl *pVtbl;
    LONG refCount;
    HWND hwnd;
} MinimalClientSite;

typedef struct {
    IOleInPlaceSiteVtbl *pVtbl;
    LONG refCount;
    HWND hwnd;
} MinimalInPlaceSite;

typedef struct {
    IOleInPlaceFrameVtbl *pVtbl;
    LONG refCount;
} MinimalInPlaceFrame;

/* IOleClientSite methods */
HRESULT STDMETHODCALLTYPE ClientSite_QueryInterface(IOleClientSite *pThis, REFIID riid, void **ppvObject) {
    if (!ppvObject) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IOleClientSite)) {
        *ppvObject = pThis;
        pThis->lpVtbl->AddRef(pThis);
        return S_OK;
    }
    if (IsEqualIID(riid, &IID_IOleInPlaceSite)) {
        MinimalClientSite *pSite = (MinimalClientSite *)pThis;
        *ppvObject = (IOleInPlaceSite *)((char *)pSite + sizeof(MinimalClientSite));
        return S_OK;
    }
    *ppvObject = NULL;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE ClientSite_AddRef(IOleClientSite *pThis) {
    MinimalClientSite *pSite = (MinimalClientSite *)pThis;
    return ++pSite->refCount;
}

ULONG STDMETHODCALLTYPE ClientSite_Release(IOleClientSite *pThis) {
    MinimalClientSite *pSite = (MinimalClientSite *)pThis;
    if (--pSite->refCount == 0) {
        free(pSite);
        return 0;
    }
    return pSite->refCount;
}

HRESULT STDMETHODCALLTYPE ClientSite_SaveObject(IOleClientSite *pThis) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE ClientSite_GetMoniker(IOleClientSite *pThis, DWORD dwAssign, DWORD dwWhichMoniker, IMoniker **ppmk) {
    if (ppmk) *ppmk = NULL;
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE ClientSite_GetContainer(IOleClientSite *pThis, IOleContainer **ppContainer) {
    if (ppContainer) *ppContainer = NULL;
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE ClientSite_ShowObject(IOleClientSite *pThis) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE ClientSite_OnShowWindow(IOleClientSite *pThis, BOOL fShow) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE ClientSite_RequestNewObjectLayout(IOleClientSite *pThis) {
    return E_NOTIMPL;
}

IOleClientSiteVtbl clientSiteVtbl = {
    ClientSite_QueryInterface,
    ClientSite_AddRef,
    ClientSite_Release,
    ClientSite_SaveObject,
    ClientSite_GetMoniker,
    ClientSite_GetContainer,
    ClientSite_ShowObject,
    ClientSite_OnShowWindow,
    ClientSite_RequestNewObjectLayout
};

/* IOleInPlaceSite methods */
HRESULT STDMETHODCALLTYPE InPlaceSite_QueryInterface(IOleInPlaceSite *pThis, REFIID riid, void **ppvObject) {
    if (!ppvObject) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IOleInPlaceSite)) {
        *ppvObject = pThis;
        pThis->lpVtbl->AddRef(pThis);
        return S_OK;
    }
    if (IsEqualIID(riid, &IID_IOleInPlaceFrame)) {
        MinimalInPlaceSite *pSite = (MinimalInPlaceSite *)pThis;
        *ppvObject = (IOleInPlaceFrame *)((char *)pSite + sizeof(MinimalInPlaceSite));
        return S_OK;
    }
    *ppvObject = NULL;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE InPlaceSite_AddRef(IOleInPlaceSite *pThis) {
    MinimalInPlaceSite *pSite = (MinimalInPlaceSite *)pThis;
    return ++pSite->refCount;
}

ULONG STDMETHODCALLTYPE InPlaceSite_Release(IOleInPlaceSite *pThis) {
    MinimalInPlaceSite *pSite = (MinimalInPlaceSite *)pThis;
    if (--pSite->refCount == 0) {
        free(pSite);
        return 0;
    }
    return pSite->refCount;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_GetWindow(IOleInPlaceSite *pThis, HWND *phwnd) {
    MinimalInPlaceSite *pSite = (MinimalInPlaceSite *)pThis;
    if (phwnd) *phwnd = pSite->hwnd;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_ContextSensitiveHelp(IOleInPlaceSite *pThis, BOOL fEnterMode) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_CanInPlaceActivate(IOleInPlaceSite *pThis) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_OnInPlaceActivate(IOleInPlaceSite *pThis) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_OnUIActivate(IOleInPlaceSite *pThis) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_GetWindowContext(IOleInPlaceSite *pThis, IOleInPlaceFrame **ppFrame,
    IOleInPlaceUIWindow **ppDoc, LPRECT lprcPosRect, LPRECT lprcClipRect, LPOLEINPLACEFRAMEINFO lpFrameInfo) {
    MinimalInPlaceSite *pSite = (MinimalInPlaceSite *)pThis;
    if (ppFrame) {
        *ppFrame = (IOleInPlaceFrame *)((char *)pSite + sizeof(MinimalInPlaceSite));
        (*ppFrame)->lpVtbl->AddRef(*ppFrame);
    }
    if (ppDoc) *ppDoc = NULL;
    if (lprcPosRect) SetRect(lprcPosRect, 0, 0, 800, 600);
    if (lprcClipRect) SetRect(lprcClipRect, 0, 0, 800, 600);
    if (lpFrameInfo) {
        lpFrameInfo->cb = sizeof(OLEINPLACEFRAMEINFO);
        lpFrameInfo->fMDIApp = FALSE;
        lpFrameInfo->hwndFrame = pSite->hwnd;
        lpFrameInfo->haccel = NULL;
        lpFrameInfo->cAccelEntries = 0;
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_Scroll(IOleInPlaceSite *pThis, SIZE scrollExtant) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_OnUIDeactivate(IOleInPlaceSite *pThis, BOOL fUndoable) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_OnInPlaceDeactivate(IOleInPlaceSite *pThis) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_DiscardUndoState(IOleInPlaceSite *pThis) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_DeactivateAndUndo(IOleInPlaceSite *pThis) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceSite_OnPosRectChange(IOleInPlaceSite *pThis, LPCRECT lprcPosRect) {
    return S_OK;
}

IOleInPlaceSiteVtbl inPlaceSiteVtbl = {
    InPlaceSite_QueryInterface,
    InPlaceSite_AddRef,
    InPlaceSite_Release,
    InPlaceSite_GetWindow,
    InPlaceSite_ContextSensitiveHelp,
    InPlaceSite_CanInPlaceActivate,
    InPlaceSite_OnInPlaceActivate,
    InPlaceSite_OnUIActivate,
    InPlaceSite_GetWindowContext,
    InPlaceSite_Scroll,
    InPlaceSite_OnUIDeactivate,
    InPlaceSite_OnInPlaceDeactivate,
    InPlaceSite_DiscardUndoState,
    InPlaceSite_DeactivateAndUndo,
    InPlaceSite_OnPosRectChange
};

/* IOleInPlaceFrame methods */
HRESULT STDMETHODCALLTYPE InPlaceFrame_QueryInterface(IOleInPlaceFrame *pThis, REFIID riid, void **ppvObject) {
    if (!ppvObject) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IOleInPlaceFrame)) {
        *ppvObject = pThis;
        pThis->lpVtbl->AddRef(pThis);
        return S_OK;
    }
    *ppvObject = NULL;
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE InPlaceFrame_AddRef(IOleInPlaceFrame *pThis) {
    MinimalInPlaceFrame *pFrame = (MinimalInPlaceFrame *)pThis;
    return ++pFrame->refCount;
}

ULONG STDMETHODCALLTYPE InPlaceFrame_Release(IOleInPlaceFrame *pThis) {
    MinimalInPlaceFrame *pFrame = (MinimalInPlaceFrame *)pThis;
    if (--pFrame->refCount == 0) {
        free(pFrame);
        return 0;
    }
    return pFrame->refCount;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_GetWindow(IOleInPlaceFrame *pThis, HWND *phwnd) {
    if (phwnd) *phwnd = NULL;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_ContextSensitiveHelp(IOleInPlaceFrame *pThis, BOOL fEnterMode) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_GetBorder(IOleInPlaceFrame *pThis, LPRECT lprectBorder) {
    if (lprectBorder) SetRect(lprectBorder, 0, 0, 0, 0);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_RequestBorderSpace(IOleInPlaceFrame *pThis, LPCBORDERWIDTHS pborderwidths) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_SetBorderSpace(IOleInPlaceFrame *pThis, LPCBORDERWIDTHS pborderwidths) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_SetActiveObject(IOleInPlaceFrame *pThis, IOleInPlaceActiveObject *pActiveObject, LPCOLESTR pszObjName) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_InsertMenus(IOleInPlaceFrame *pThis, HMENU hmenuShared, LPOLEMENUGROUPWIDTHS lpMenuWidths) {
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_SetMenu(IOleInPlaceFrame *pThis, HMENU hmenuShared, HOLEMENU holemenu, HWND hwndActiveObject) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_RemoveMenus(IOleInPlaceFrame *pThis, HMENU hmenuShared) {
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_SetStatusText(IOleInPlaceFrame *pThis, LPCOLESTR pszStatusText) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_EnableModeless(IOleInPlaceFrame *pThis, BOOL fEnable) {
    return S_OK;
}

HRESULT STDMETHODCALLTYPE InPlaceFrame_TranslateAccelerator(IOleInPlaceFrame *pThis, LPMSG lpmsg, WORD wID) {
    return S_FALSE;
}

IOleInPlaceFrameVtbl inPlaceFrameVtbl = {
    InPlaceFrame_QueryInterface,
    InPlaceFrame_AddRef,
    InPlaceFrame_Release,
    InPlaceFrame_GetWindow,
    InPlaceFrame_ContextSensitiveHelp,
    InPlaceFrame_GetBorder,
    InPlaceFrame_RequestBorderSpace,
    InPlaceFrame_SetBorderSpace,
    InPlaceFrame_SetActiveObject,
    InPlaceFrame_InsertMenus,
    InPlaceFrame_SetMenu,
    InPlaceFrame_RemoveMenus,
    InPlaceFrame_SetStatusText,
    InPlaceFrame_EnableModeless,
    InPlaceFrame_TranslateAccelerator
};

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_QUIT:
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProc(hwnd, msg, wParam, lParam);
    }
}

int main(int argc, char **argv) {
    HRESULT hr;
    HWND hwnd = NULL;
    IOleObject *pOleObj = NULL;
    IWebBrowser2 *pBrowser = NULL;
    IDispatch *pDispDoc = NULL;
    IHTMLDocument2 *pHtmlDoc = NULL;
    BSTR bstrUrl = NULL;
    BSTR bstrTitle = NULL;
    VARIANT vUrl, vEmpty;
    MinimalClientSite *pClientSite = NULL;
    MinimalInPlaceSite *pInPlaceSite = NULL;
    MinimalInPlaceFrame *pInPlaceFrame = NULL;
    time_t startTime;
    READYSTATE readyState;
    char szUrl[1024];
    int len;

    if (argc < 2) {
        fprintf(stderr, "Usage: %s <html-file-path>\n", argv[0]);
        return 1;
    }

    /* Initialize COM */
    hr = OleInitialize(NULL);
    if (FAILED(hr)) {
        fprintf(stderr, "OleInitialize failed: 0x%08lx\n", hr);
        return 1;
    }

    /* Register window class */
    WNDCLASS wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.lpszClassName = "WBHostClass";
    wc.hInstance = GetModuleHandle(NULL);
    if (!RegisterClass(&wc)) {
        fprintf(stderr, "RegisterClass failed\n");
        OleUninitialize();
        return 1;
    }

    /* Create window (offscreen, not visible) */
    hwnd = CreateWindow("WBHostClass", "", WS_OVERLAPPEDWINDOW, 
                        CW_USEDEFAULT, CW_USEDEFAULT, 800, 600, 
                        NULL, NULL, GetModuleHandle(NULL), NULL);
    if (!hwnd) {
        fprintf(stderr, "CreateWindow failed\n");
        OleUninitialize();
        return 1;
    }

    /* Allocate and initialize client site */
    pClientSite = (MinimalClientSite *)malloc(sizeof(MinimalClientSite) + sizeof(MinimalInPlaceSite) + sizeof(MinimalInPlaceFrame));
    if (!pClientSite) {
        fprintf(stderr, "malloc failed\n");
        DestroyWindow(hwnd);
        OleUninitialize();
        return 1;
    }
    pClientSite->pVtbl = &clientSiteVtbl;
    pClientSite->refCount = 1;
    pClientSite->hwnd = hwnd;

    pInPlaceSite = (MinimalInPlaceSite *)((char *)pClientSite + sizeof(MinimalClientSite));
    pInPlaceSite->pVtbl = &inPlaceSiteVtbl;
    pInPlaceSite->refCount = 1;
    pInPlaceSite->hwnd = hwnd;

    pInPlaceFrame = (MinimalInPlaceFrame *)((char *)pInPlaceSite + sizeof(MinimalInPlaceSite));
    pInPlaceFrame->pVtbl = &inPlaceFrameVtbl;
    pInPlaceFrame->refCount = 1;

    /* Create WebBrowser control */
    hr = CoCreateInstance(&CLSID_WebBrowser, NULL, CLSCTX_INPROC_SERVER, 
                          &IID_IOleObject, (void **)&pOleObj);
    if (FAILED(hr)) {
        fprintf(stderr, "CoCreateInstance(WebBrowser) failed: 0x%08lx\n", hr);
        free(pClientSite);
        DestroyWindow(hwnd);
        OleUninitialize();
        return 1;
    }

    /* Set client site */
    hr = pOleObj->lpVtbl->SetClientSite(pOleObj, (IOleClientSite *)pClientSite);
    if (FAILED(hr)) {
        fprintf(stderr, "SetClientSite failed: 0x%08lx\n", hr);
        pOleObj->lpVtbl->Release(pOleObj);
        free(pClientSite);
        DestroyWindow(hwnd);
        OleUninitialize();
        return 1;
    }

    /* Activate in-place */
    VariantInit(&vEmpty);
    hr = pOleObj->lpVtbl->DoVerb(pOleObj, OLEIVERB_INPLACEACTIVATE, NULL, 
                                 (IOleClientSite *)pClientSite, 0, hwnd, NULL);
    if (FAILED(hr)) {
        fprintf(stderr, "DoVerb failed: 0x%08lx\n", hr);
        pOleObj->lpVtbl->Release(pOleObj);
        free(pClientSite);
        DestroyWindow(hwnd);
        OleUninitialize();
        return 1;
    }

    /* Query for IWebBrowser2 */
    hr = pOleObj->lpVtbl->QueryInterface(pOleObj, &IID_IWebBrowser2, (void **)&pBrowser);
    if (FAILED(hr)) {
        fprintf(stderr, "QueryInterface(IWebBrowser2) failed: 0x%08lx\n", hr);
        pOleObj->lpVtbl->Release(pOleObj);
        free(pClientSite);
        DestroyWindow(hwnd);
        OleUninitialize();
        return 1;
    }

    /* Build file:// URL from argv[1] */
    len = snprintf(szUrl, sizeof(szUrl) - 1, "file:///%s", argv[1]);
    /* Convert backslashes to forward slashes */
    for (int i = 8; i < len; i++) {
        if (szUrl[i] == '\\') szUrl[i] = '/';
    }
    szUrl[len] = 0;

    /* Convert to BSTR and VARIANT */
    {
        int wLen = MultiByteToWideChar(CP_ACP, 0, szUrl, -1, NULL, 0);
        WCHAR *wszUrl = (WCHAR *)malloc(wLen * sizeof(WCHAR));
        MultiByteToWideChar(CP_ACP, 0, szUrl, -1, wszUrl, wLen);
        bstrUrl = SysAllocString(wszUrl);
        free(wszUrl);
    }

    /* Navigate */
    VariantInit(&vUrl);
    vUrl.vt = VT_BSTR;
    vUrl.bstrVal = bstrUrl;
    hr = pBrowser->lpVtbl->Navigate2(pBrowser, &vUrl, &vEmpty, &vEmpty, &vEmpty, &vEmpty);
    if (FAILED(hr)) {
        fprintf(stderr, "Navigate2 failed: 0x%08lx\n", hr);
        VariantClear(&vUrl);
        pBrowser->lpVtbl->Release(pBrowser);
        pOleObj->lpVtbl->Release(pOleObj);
        free(pClientSite);
        DestroyWindow(hwnd);
        OleUninitialize();
        return 1;
    }

    VariantClear(&vUrl);

    /* Message pump with timeout */
    startTime = time(NULL);
    while (1) {
        MSG msg;
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) break;
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        } else {
            /* Poll ready state */
            hr = pBrowser->lpVtbl->get_ReadyState(pBrowser, &readyState);
            if (SUCCEEDED(hr) && readyState == READYSTATE_COMPLETE) {
                break;
            }
            /* Check timeout (15 seconds) */
            if (time(NULL) - startTime > 15) {
                break;
            }
            Sleep(100);
        }
    }

    /* Get document title */
    hr = pBrowser->lpVtbl->get_Document(pBrowser, &pDispDoc);
    if (SUCCEEDED(hr) && pDispDoc) {
        hr = pDispDoc->lpVtbl->QueryInterface(pDispDoc, &IID_IHTMLDocument2, (void **)&pHtmlDoc);
        if (SUCCEEDED(hr) && pHtmlDoc) {
            hr = pHtmlDoc->lpVtbl->get_title(pHtmlDoc, &bstrTitle);
            if (SUCCEEDED(hr) && bstrTitle) {
                /* Convert BSTR to multibyte and print */
                int len = WideCharToMultiByte(CP_UTF8, 0, bstrTitle, -1, NULL, 0, NULL, NULL);
                char *szTitle = (char *)malloc(len);
                WideCharToMultiByte(CP_UTF8, 0, bstrTitle, -1, szTitle, len, NULL, NULL);
                printf("TITLE=%s\n", szTitle);
                fflush(stdout);
                free(szTitle);
                SysFreeString(bstrTitle);
            }
            pHtmlDoc->lpVtbl->Release(pHtmlDoc);
        }
        pDispDoc->lpVtbl->Release(pDispDoc);
    }

    /* Cleanup */
    pBrowser->lpVtbl->Release(pBrowser);
    pOleObj->lpVtbl->Release(pOleObj);
    free(pClientSite);
    DestroyWindow(hwnd);
    OleUninitialize();

    return 0;
}

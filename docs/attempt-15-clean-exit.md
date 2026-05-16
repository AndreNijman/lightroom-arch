# Attempt 15 — Lightroom exits cleanly (close shortcut + titlebar button)

Lightroom ran fine but would not *quit* properly. Two close paths, both
broken in different ways:

- **Hyprland close shortcut** (`Super+Q` → `killactive`): a complete no-op.
  The window stayed, every Wine process kept running.
- **Titlebar close button**: closed Lightroom, but the exit aborted on an
  unimplemented Wine function, and helper processes were left behind.

Turning either into a real, clean quit took two Wine patches.

## Bug 1 — the close shortcut does nothing

Lightroom runs inside a Wine **virtual desktop** (`explorer.exe` hosts a
desktop window; Lightroom's window lives inside it). Hyprland's
`killactive` sends `WM_DELETE_WINDOW` to the desktop's X window.

`winex11`'s `handle_wm_protocols` (`dlls/winex11.drv/event.c`) has a
special case for the desktop window:

```c
if (hwnd == NtUserGetDesktopWindow())
{
    send_message( hwnd, WM_SYSCOMMAND, SC_CLOSE, 0 );
    return;
}
```

`SC_CLOSE` on the desktop window reaches `desktop_wnd_proc`
(`programs/explorer/desktop.c`), which calls `ExitWindows(0, 0)` — a
session logoff. A logoff broadcasts `WM_QUERYENDSESSION`; any app can veto
it. Lightroom vetoes / stalls the broadcast, the logoff is abandoned, and
**nothing happens**. Confirmed: `closewindow` on the desktop X window left
all 11 Wine processes alive and the window mapped.

The titlebar close button works because it sends `SC_CLOSE` straight to
Lightroom's *own* window — a direct app close, no logoff, no veto.

### Fix — route the close to the focused app window

`winex11-wm-close-fix.patch`. In a virtual desktop, a `WM_DELETE_WINDOW`
on the desktop is now routed to `SC_CLOSE` on the **focused application
window** — exactly what the titlebar button does, what Alt+F4 does:

```c
HWND fg = NtUserGetForegroundWindow();
if (is_virtual_desktop() && fg && fg != hwnd)
    send_message( fg, WM_SYSCOMMAND, SC_CLOSE, 0 );
else
    send_message( hwnd, WM_SYSCOMMAND, SC_CLOSE, 0 );
```

With this, `killactive` reaches Lightroom's own close path. Verified with
an `ERR` trace: `wm_delete on desktop: fg=0x100a6 vdesktop=1` → Lightroom
began shutting down.

## Bug 2 — shutdown aborts on UiaDisconnectAllProviders

Both close paths now reached Lightroom's shutdown, and both hit the same
wall:

```
wine: Call from ... to unimplemented function
      ext-ms-win-uiacore-l1-1-2.dll.UiaDisconnectAllProviders, aborting
```

During shutdown Lightroom calls `UiaDisconnectAllProviders()` (UI
Automation). Stock Wine's `uiautomationcore` **never exported it** — the
spec entry was commented out:

```
#@ stub UiaDisconnectAllProviders
```

The call resolved to an unimplemented stub and Wine aborted. Sometimes the
process still died, sometimes it hung — an unreliable exit either way.

### Fix — export it as a no-op

`uiautomationcore-disconnect-all-providers.patch`. `uiautomationcore` now
exports `UiaDisconnectAllProviders` as a no-op returning `S_OK`
(`uia_provider.c`, `uiautomationcore.spec`, `include/uiautomationcoreapi.h`).
Per-process UI Automation provider state is freed at process exit anyway,
so doing nothing is safe — and Lightroom's shutdown path completes
normally.

## Result

Both fixes ship as prebuilt binaries in `wine-patches/` (`winex11.so` —
which also carries the attempt-14 flicker fix — and `uiautomationcore.dll`);
`run-lightroom.sh` installs them idempotently and keeps the stock files as
`.orig`. A `trap` in `run-lightroom.sh` runs `scripts/kill-wine.sh` when the
script exits, draining the `explorer.exe` desktop host and service helpers
that linger after `lightroom.exe` itself is gone.

Verified, both close paths:

| Close path | Before | After |
|------------|--------|-------|
| Hyprland `Super+Q` (`killactive`) | no-op, 11 procs alive | 0 procs, 0 windows, no abort |
| Titlebar close button | aborts, helpers leak | 0 procs, 0 windows, no abort |

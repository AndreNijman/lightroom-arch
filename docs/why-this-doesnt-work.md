# Why This Doesn't Work

This repository tested Lightroom installation paths on Arch Linux in April 2026. None reached a working Lightroom install. The failures are not isolated shell-script defects; they are upstream installer and runtime blockers.

## Lutris, Lightroom 6.14 target

The Lutris approach targeted old perpetual Lightroom media, with Lightroom 6.14 as the fallback target. That path is blocked upstream because Adobe ended Lightroom 6.14 download support on 2023-12-31, and the ProDesignTools direct Adobe payload links returned HTTP 403 as of 2026-04-28.

The installer provided during validation was not a Lightroom 6.14 offline installer. It was a Creative Cloud bootstrapper:

```text
Lightroom_Set-Up_707q.exe contains a manifest description of `Creative Cloud Set-up`; it appears to be a Creative Cloud bootstrapper, not an offline Lightroom 5.x installer.
```

The bootstrapper exited without installing Lightroom:

```text
[ERROR] Lightroom executable not found after install: /home/andre/.local/share/lightroom-arch/prefixes/lightroom-creative-cloud-bootstrapper/drive_c/Program Files/Adobe/Adobe Photoshop Lightroom/lightroom.exe
```

## Wine vanilla + winetricks, Lightroom cloud

The vanilla Wine Creative Cloud approach failed before Creative Cloud Desktop installed. The blocker was the Adobe bootstrapper's IE/MSHTML/JScript dependency path. The current winetricks package could not apply the historical `mshtml` workaround:

```text
Unknown arg mshtml
0148:fixme:mshtml:process_meta_element Unsupported document mode L"chrome=1"
0148:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000001
0148:fixme:jscript:JScriptProperty_SetProperty Unimplemented property 70000002
0148:fixme:mshtml:ActiveScriptSite_OnScriptError (0343DC70)->(03445888)
[ERROR] Lightroom cloud executable not found after install: /home/andre/.wine-lightroom-cc/drive_c/Program Files/Adobe/Adobe Lightroom/Lightroom.exe
```

## Bottles caffe + browser deps, Lightroom cloud

Bottles with `caffe-9.7` and added browser dependencies reached the same family of blocker from a different angle. Enabling native browser DLLs exposed an unsatisfied `iertutil.dll` dependency for Wine's `wininet` path:

```text
err:module:import_dll Library iertutil.dll (which is needed by L"C:\\windows\\system32\\wininet.dll") not found
err:module:DelayLoadFailureHook failed to delay load wininet.dll.InternetOpenA
wine: Unimplemented function wininet.dll.InternetOpenA called ... starting debugger...
```

After dependency ordering was fixed, WebView2 installed and the bootstrapper launched, but no Creative Cloud Desktop install appeared. The process looped on WinRT, RPC, and OLE failures.

## Bottles soda + default deps, Lightroom cloud

Bottles with `soda-9.0-1` created a hidden Xwayland window titled `Creative Cloud Installer`. After mapping it manually, the surface was black and no Creative Cloud Desktop executable appeared. The local run log showed repeated missing COM class and RPC binding failures:

```text
02dc:err:ole:com_get_class_object class {2b72133b-3f5b-4602-8952-803546ce3344} not registered
02dc:err:ole:com_get_class_object no class object {2b72133b-3f5b-4602-8952-803546ce3344} could be created for context 0x1
0048:err:rpc:RpcAssoc_BindConnection rejected bind for reason 0
066c:err:rpc:RpcAssoc_BindConnection rejected bind for reason 0
```

## Conclusion

Every Wine runtime tested terminates because Adobe's modern installers require working IE/MSHTML/COM integration that no longer exists in Wine in 2026. This is structural, not a configuration problem. Future attempts on different runners will hit the same wall at different depths unless they materially replace or bypass Adobe's embedded browser, authentication, and COM installer stack.

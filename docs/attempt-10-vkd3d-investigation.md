# Attempt 10: The vkd3d Crash — Investigated, No Upstream Bug

## Goal of this attempt

Attempt 9 left photo editing working only with GPU acceleration **off**,
because opening a photo crashed in `libvkd3d-1.dll`. The plan here was to
find the Wine/vkd3d bug, fix it, and upstream the patch.

## What the crash actually is

The crash, captured with `VKD3D_DEBUG=warn` and `WINEDEBUG=+seh`:

```
EXCEPTION_ACCESS_VIOLATION_READ  addr=0x0
 0  libvkd3d-1.dll + 0x3c5d0
 1  dxgi.dll + 0x6d9a          (d3d12_swapchain_init)
 2  dxgi.dll + 0xe5ec          (d3d12_swapchain_create)
 ...
 9  CameraRaw.dll
```

Immediately before it: `dxgi:d3d12_swapchain_init Ignoring swap effect`.
So it is **swapchain creation**, not device creation.

Reading Wine's `dlls/dxgi/swapchain.c`, `d3d12_swapchain_init` does:

```c
vk_instance = vkd3d_instance_get_vk_instance(vkd3d_instance_from_device(device));
vk_physical_device = vkd3d_get_vk_physical_device(device);
vk_device = vkd3d_get_vk_device(device);
```

And vkd3d's accessors (`libs/vkd3d/device.c`) are raw struct casts:

```c
VkDevice vkd3d_get_vk_device(ID3D12Device *device)
{
    struct d3d12_device *d3d12_device = impl_from_ID3D12Device9((ID3D12Device9 *)device);
    return d3d12_device->vk_device;
}
```

`impl_from_ID3D12Device9` is pointer arithmetic with no validation. It is
only correct for an `ID3D12Device` that **this same vkd3d** created.

## Root cause — a self-inflicted misconfiguration

Attempt 9 copied **vkd3d-proton**'s `d3d12core.dll` into the prefix and
set `d3d12=n`. That made CameraRaw's D3D12 device a *vkd3d-proton* object.
But Wine's builtin `dxgi.dll` is built against Wine's *own* `libvkd3d`.
When CameraRaw asked DXGI for a D3D12 swapchain, `d3d12_swapchain_init`
passed the vkd3d-proton device to Wine-libvkd3d's `vkd3d_*` accessors,
which cast it to the wrong struct layout, read a garbage/NULL pointer,
and dereferenced it.

Wine's builtin dxgi and vkd3d-proton's d3d12 are **two different D3D12
implementations and cannot be mixed**. This is not a Wine bug — it is an
unsupported configuration that attempt 9 created.

## The decisive test

Ran LR with a **consistent all-Wine-builtin D3D12 stack**:

```
WINEDLLOVERRIDES="...;dxgi=b;d3d12=b;d3d12core=b"
```

with GPU acceleration **on**. Result:

- `d3d12_swapchain_init` runs to completion — no crash
- LR opens photos in the Develop module, renders them full-size
- The Edit panel works — dragging Exposure GPU-darkens the photo live
- No crash dump, no `Adobe Crash Processor`

## Conclusion

**There is no upstream Wine/vkd3d bug here.** The crash was caused by
mixing vkd3d-proton's D3D12 with Wine's builtin dxgi. With the whole
D3D12 stack kept builtin (`d3d12=b;d3d12core=b`), Lightroom runs
GPU-accelerated and crash-free — a better result than the attempt-9
GPU-off workaround.

`run-lightroom.sh` now uses the all-builtin D3D12 config with GPU on.
The attempt-9 GPU-off workaround and the vkd3d-proton DLL swap are
both withdrawn.

### Why no patch was submitted

The upstreaming plan assumed a real bug in `wine/vkd3d`. Investigation
showed there is none: Wine's dxgi/vkd3d D3D12-swapchain code is correct
for its own device objects. Hardening it to "not crash when handed a
foreign vkd3d-proton device" would paper over an unsupported mix and
would be rejected upstream — the device is foreign either way. The
honest outcome is the configuration fix above, not a patch.

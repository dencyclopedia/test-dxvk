// D3D8 path of dxprobe (separate file: d3d8.h and d3d9.h cannot be included together).
#include "common.h"
#include <d3d8.h>

bool run_d3d8(HWND hwnd, int W, int H, int frames, int draws, double hold, Result& R) {
  double t0 = now_ms();
  HMODULE dll = LoadLibraryA("d3d8.dll"); if (!dll) { R.error = "LoadLibrary d3d8.dll failed"; return false; }
  auto create = (IDirect3D8*(WINAPI*)(UINT))GetProcAddress(dll, "Direct3DCreate8");
  IDirect3D8* d3d = create ? create(220) : nullptr; if (!d3d) { R.error = "Direct3DCreate8 returned NULL"; return false; }
  D3DADAPTER_IDENTIFIER8 id = {}; d3d->GetAdapterIdentifier(0, 0, &id); R.adapter = id.Description; R.vendor = id.VendorId; R.device = id.DeviceId;
  D3DDISPLAYMODE dm = {}; d3d->GetAdapterDisplayMode(0, &dm);
  D3DPRESENT_PARAMETERS pp = {}; pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.BackBufferFormat = dm.Format;
  pp.BackBufferWidth = W; pp.BackBufferHeight = H; pp.hDeviceWindow = hwnd;
  IDirect3DDevice8* dev = nullptr;
  HRESULT hr = d3d->CreateDevice(0, D3DDEVTYPE_HAL, hwnd, D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
  if (FAILED(hr)) { char b[64]; sprintf(b, "CreateDevice hr=0x%08lx", (unsigned long)hr); R.error = b; return false; }
  R.initMs = now_ms() - t0;
  dev->SetVertexShader(D3DFVF_XYZRHW | D3DFVF_DIFFUSE); dev->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE); dev->SetRenderState(D3DRS_LIGHTING, FALSE);
  double start = now_ms();
  for (int f = 0; f < frames || (now_ms() - start) < hold * 1000; f++) {
    double a = now_ms(); pump();
    dev->Clear(0, nullptr, D3DCLEAR_TARGET, 0xff101418, 1.0f, 0); dev->BeginScene();
    for (int i = 0; i < draws; i++) { VtxT v[3]; tri(v, i, draws, f * 0.02f, W, H); dev->DrawPrimitiveUP(D3DPT_TRIANGLELIST, 1, v, sizeof(VtxT)); }
    dev->EndScene(); if (FAILED(dev->Present(nullptr, nullptr, nullptr, nullptr))) { R.error = "Present failed"; return false; }
    if (f < frames) R.ft.push_back(now_ms() - a);
  }
  dev->Release(); d3d->Release(); return true;
}


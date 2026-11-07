// dxprobe: a tiny Direct3D 8/9/11 test program used by the dxvk.dev test lab.
// It renders a grid of coloured triangles with one draw call per triangle, so
// the CPU cost of each draw call (what DXVK translates) dominates the frame.
//
//   dxprobe.exe <d3d8|d3d9|d3d11> [frames=600] [draws=2000] [holdSeconds=0]
//
// Writes one JSON object to stdout and to dxprobe-<api>.json in the working
// directory: which DLL file was actually loaded, adapter name/vendor reported
// to the game, init time, frame-time statistics. Exit code 0 = rendered OK.
#include "common.h"
#include <d3d9.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d3dcompiler.h>

LARGE_INTEGER g_freq;
bool run_d3d8(HWND, int, int, int, int, double, Result&);

static bool run_d3d9(HWND hwnd, int W, int H, int frames, int draws, double hold, Result& R) {
  double t0 = now_ms();
  HMODULE dll = LoadLibraryA("d3d9.dll"); if (!dll) { R.error = "LoadLibrary d3d9.dll failed"; return false; }
  auto create = (IDirect3D9*(WINAPI*)(UINT))GetProcAddress(dll, "Direct3DCreate9");
  IDirect3D9* d3d = create ? create(D3D_SDK_VERSION) : nullptr; if (!d3d) { R.error = "Direct3DCreate9 returned NULL"; return false; }
  D3DADAPTER_IDENTIFIER9 id = {}; d3d->GetAdapterIdentifier(0, 0, &id); R.adapter = id.Description; R.vendor = id.VendorId; R.device = id.DeviceId;
  D3DPRESENT_PARAMETERS pp = {}; pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.BackBufferFormat = D3DFMT_X8R8G8B8;
  pp.BackBufferWidth = W; pp.BackBufferHeight = H; pp.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE; pp.hDeviceWindow = hwnd;
  IDirect3DDevice9* dev = nullptr;
  HRESULT hr = d3d->CreateDevice(0, D3DDEVTYPE_HAL, hwnd, D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
  if (FAILED(hr)) { char b[64]; sprintf(b, "CreateDevice hr=0x%08lx", (unsigned long)hr); R.error = b; return false; }
  R.extra = "\"availableTextureMemMB\":" + std::to_string(dev->GetAvailableTextureMem() / (1024 * 1024));
  R.initMs = now_ms() - t0;
  dev->SetFVF(D3DFVF_XYZRHW | D3DFVF_DIFFUSE); dev->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE); dev->SetRenderState(D3DRS_LIGHTING, FALSE);
  double start = now_ms();
  for (int f = 0; f < frames || (now_ms() - start) < hold * 1000; f++) {
    double a = now_ms(); pump();
    dev->Clear(0, nullptr, D3DCLEAR_TARGET, 0xff101418, 1.0f, 0); dev->BeginScene();
    for (int i = 0; i < draws; i++) { VtxT v[3]; tri(v, i, draws, f * 0.02f, W, H); dev->DrawPrimitiveUP(D3DPT_TRIANGLELIST, 1, v, sizeof(VtxT)); }
    dev->EndScene(); hr = dev->Present(nullptr, nullptr, nullptr, nullptr);
    if (FAILED(hr)) { R.error = "Present failed"; return false; }
    if (f < frames) R.ft.push_back(now_ms() - a);
  }
  dev->Release(); d3d->Release(); return true;
}

static const char* HLSL =
  "cbuffer C : register(b0) { float4 xf; float4 col; };\n"
  "struct V { float4 p : SV_Position; float4 c : COLOR; };\n"
  "V vs(uint id : SV_VertexID) { float a = xf.z + id * 2.0944; V o; o.p = float4(xf.x + xf.w * cos(a), xf.y + xf.w * sin(a), 0.5, 1); o.c = col; return o; }\n"
  "float4 ps(V i) : SV_Target { return i.c; }\n";

static bool run_d3d11(HWND hwnd, int W, int H, int frames, int draws, double hold, Result& R) {
  double t0 = now_ms();
  HMODULE dll = LoadLibraryA("d3d11.dll"); if (!dll) { R.error = "LoadLibrary d3d11.dll failed"; return false; }
  auto create = (PFN_D3D11_CREATE_DEVICE_AND_SWAP_CHAIN)GetProcAddress(dll, "D3D11CreateDeviceAndSwapChain");
  HMODULE comp = LoadLibraryA("d3dcompiler_47.dll"); if (!comp) { R.error = "d3dcompiler_47.dll missing"; return false; }
  auto compile = (pD3DCompile)GetProcAddress(comp, "D3DCompile");
  DXGI_SWAP_CHAIN_DESC sd = {}; sd.BufferCount = 2; sd.BufferDesc.Width = W; sd.BufferDesc.Height = H; sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.OutputWindow = hwnd; sd.SampleDesc.Count = 1; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  ID3D11Device* dev = nullptr; ID3D11DeviceContext* ctx = nullptr; IDXGISwapChain* sc = nullptr; D3D_FEATURE_LEVEL fl;
  HRESULT hr = create(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0, D3D11_SDK_VERSION, &sd, &sc, &dev, &fl, &ctx);
  if (FAILED(hr)) { char b[64]; sprintf(b, "D3D11CreateDeviceAndSwapChain hr=0x%08lx", (unsigned long)hr); R.error = b; return false; }
  IDXGIDevice* xd = nullptr; IDXGIAdapter* ad = nullptr; DXGI_ADAPTER_DESC desc = {};
  if (SUCCEEDED(dev->QueryInterface(__uuidof(IDXGIDevice), (void**)&xd)) && SUCCEEDED(xd->GetAdapter(&ad))) {
    ad->GetDesc(&desc); char nb[256]; WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, nb, 256, nullptr, nullptr);
    R.adapter = nb; R.vendor = desc.VendorId; R.device = desc.DeviceId;
  }
  char fls[16]; sprintf(fls, "%x_%x", (fl >> 12) & 0xf, (fl >> 8) & 0xf);
  R.extra = std::string("\"featureLevel\":\"") + fls + "\",\"dedicatedVideoMemoryMB\":" + std::to_string((unsigned long long)desc.DedicatedVideoMemory / (1024 * 1024));
  ID3DBlob *vsb = nullptr, *psb = nullptr, *err = nullptr;
  if (FAILED(compile(HLSL, strlen(HLSL), "p", nullptr, nullptr, "vs", "vs_4_0", 0, 0, &vsb, &err)) ||
      FAILED(compile(HLSL, strlen(HLSL), "p", nullptr, nullptr, "ps", "ps_4_0", 0, 0, &psb, &err))) { R.error = "shader compile failed"; return false; }
  ID3D11VertexShader* vs; ID3D11PixelShader* ps;
  dev->CreateVertexShader(vsb->GetBufferPointer(), vsb->GetBufferSize(), nullptr, &vs);
  dev->CreatePixelShader(psb->GetBufferPointer(), psb->GetBufferSize(), nullptr, &ps);
  D3D11_BUFFER_DESC bd = {}; bd.ByteWidth = 32; bd.Usage = D3D11_USAGE_DYNAMIC; bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER; bd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
  ID3D11Buffer* cb; dev->CreateBuffer(&bd, nullptr, &cb);
  D3D11_RASTERIZER_DESC rd = {}; rd.FillMode = D3D11_FILL_SOLID; rd.CullMode = D3D11_CULL_NONE; rd.DepthClipEnable = TRUE;
  ID3D11RasterizerState* rs; dev->CreateRasterizerState(&rd, &rs);
  ID3D11Texture2D* bb; sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&bb); ID3D11RenderTargetView* rtv; dev->CreateRenderTargetView(bb, nullptr, &rtv);
  R.initMs = now_ms() - t0;
  D3D11_VIEWPORT vp = { 0, 0, (float)W, (float)H, 0, 1 };
  int cols = (int)std::ceil(std::sqrt((double)draws));
  double start = now_ms();
  for (int f = 0; f < frames || (now_ms() - start) < hold * 1000; f++) {
    double a = now_ms(); pump();
    float clear[4] = { 0.063f, 0.078f, 0.094f, 1 }; ctx->ClearRenderTargetView(rtv, clear);
    ctx->OMSetRenderTargets(1, &rtv, nullptr); ctx->RSSetViewports(1, &vp); ctx->RSSetState(rs);
    ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST); ctx->VSSetShader(vs, nullptr, 0); ctx->PSSetShader(ps, nullptr, 0);
    ctx->VSSetConstantBuffers(0, 1, &cb); ctx->PSSetConstantBuffers(0, 1, &cb);
    for (int i = 0; i < draws; i++) {
      D3D11_MAPPED_SUBRESOURCE m; ctx->Map(cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &m); float* p = (float*)m.pData;
      p[0] = -1 + (i % cols + 0.5f) * 2.0f / cols; p[1] = 1 - (i / cols + 0.5f) * 2.0f / cols; p[2] = f * 0.02f + i * 0.01f; p[3] = 0.9f / cols;
      p[4] = (i * 53 % 255) / 255.f; p[5] = (i * 97 % 255) / 255.f; p[6] = (i * 151 % 255) / 255.f; p[7] = 1; ctx->Unmap(cb, 0);
      ctx->Draw(3, 0);
    }
    if (FAILED(sc->Present(0, 0))) { R.error = "Present failed"; return false; }
    if (f < frames) R.ft.push_back(now_ms() - a);
  }
  return true;
}

int main(int argc, char** argv) {
  QueryPerformanceFrequency(&g_freq);
  std::string api = argc > 1 ? argv[1] : "d3d9";
  int frames = argc > 2 ? atoi(argv[2]) : 600, draws = argc > 3 ? atoi(argv[3]) : 2000; double hold = argc > 4 ? atof(argv[4]) : 0;
  const int W = 960, H = 540;
  WNDCLASSA wc = {}; wc.lpfnWndProc = wndproc; wc.hInstance = GetModuleHandleA(nullptr); wc.lpszClassName = "dxprobe"; wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassA(&wc);
  RECT rc = { 0, 0, W, H }; AdjustWindowRect(&rc, WS_OVERLAPPEDWINDOW, FALSE);
  std::string title = "dxprobe " + api;
  HWND hwnd = CreateWindowA("dxprobe", title.c_str(), WS_OVERLAPPEDWINDOW | WS_VISIBLE, 0, 0, rc.right - rc.left, rc.bottom - rc.top, nullptr, nullptr, wc.hInstance, nullptr);
  Result R; R.api = api; bool ok = false;
  if (api == "d3d9") ok = run_d3d9(hwnd, W, H, frames, draws, hold, R);
  else if (api == "d3d8") ok = run_d3d8(hwnd, W, H, frames, draws, hold, R);
  else if (api == "d3d11") ok = run_d3d11(hwnd, W, H, frames, draws, hold, R);
  else R.error = "unknown api";
  std::vector<double> s = R.ft; std::sort(s.begin(), s.end()); double sum = 0; for (double v : s) sum += v;
  auto pct = [&](double p) { return s.empty() ? 0.0 : s[std::min(s.size() - 1, (size_t)(p * s.size()))]; };
  char buf[4096];
  snprintf(buf, sizeof buf,
    "{\"api\":\"%s\",\"arch\":\"%s\",\"ok\":%s,\"error\":\"%s\",\"adapter\":\"%s\",\"vendorId\":\"0x%04x\",\"deviceId\":\"0x%04x\","
    "\"modules\":{\"d3d8\":\"%s\",\"d3d9\":\"%s\",\"d3d11\":\"%s\",\"dxgi\":\"%s\"},\"initMs\":%.1f,\"frames\":%zu,\"draws\":%d,"
    "\"avgMs\":%.3f,\"p50Ms\":%.3f,\"p99Ms\":%.3f,\"maxMs\":%.3f,\"avgFps\":%.1f%s%s}",
    api.c_str(), sizeof(void*) == 8 ? "x64" : "x86", ok ? "true" : "false", esc(R.error).c_str(), esc(R.adapter).c_str(), R.vendor, R.device,
    esc(modpath("d3d8.dll")).c_str(), esc(modpath("d3d9.dll")).c_str(), esc(modpath("d3d11.dll")).c_str(), esc(modpath("dxgi.dll")).c_str(),
    R.initMs, s.size(), draws, s.empty() ? 0 : sum / s.size(), pct(0.5), pct(0.99), s.empty() ? 0 : s.back(),
    s.empty() ? 0 : 1000.0 * s.size() / sum, R.extra.empty() ? "" : ",", R.extra.c_str());
  puts(buf); fflush(stdout);
  std::string fn = "dxprobe-" + api + "-" + (sizeof(void*) == 8 ? "x64" : "x86") + ".json";
  if (FILE* fp = fopen(fn.c_str(), "w")) { fputs(buf, fp); fputc('\n', fp); fclose(fp); }
  DestroyWindow(hwnd);
  return ok ? 0 : 1;
}

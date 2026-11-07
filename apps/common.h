// Shared helpers for dxprobe (see dxprobe.cpp).
#pragma once
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cmath>
#include <string>
#include <vector>
#include <algorithm>
extern LARGE_INTEGER g_freq;
static inline double now_ms() { LARGE_INTEGER t; QueryPerformanceCounter(&t); return 1000.0 * t.QuadPart / g_freq.QuadPart; }
static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l) { return DefWindowProcA(h, m, w, l); }
static inline std::string modpath(const char* name) {
  HMODULE m = GetModuleHandleA(name); if (!m) return "";
  char buf[MAX_PATH] = {}; GetModuleFileNameA(m, buf, MAX_PATH); return buf;
}
static inline std::string esc(const std::string& s) {
  std::string o; for (char c : s) { if (c == '"' || c == '\\') o += '\\'; if ((unsigned char)c >= 32) o += c; } return o;
}
static inline void pump() { MSG msg; while (PeekMessageA(&msg, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); } }

struct Result { std::string api, adapter, error; unsigned vendor = 0, device = 0; double initMs = 0; std::vector<double> ft; std::string extra; };

struct VtxT { float x, y, z, rhw; DWORD c; };
static inline void tri(VtxT* v, int i, int n, float t, int W, int H) {
  int cols = (int)std::ceil(std::sqrt((double)n)); float cw = (float)W / cols, ch = (float)H / cols;
  float cx = (i % cols + 0.5f) * cw, cy = (i / cols + 0.5f) * ch, r = 0.45f * std::min(cw, ch), a = t + i * 0.01f;
  DWORD col = 0xff000000 | ((i * 53 % 255) << 16) | ((i * 97 % 255) << 8) | (i * 151 % 255);
  for (int k = 0; k < 3; k++) { float ang = a + k * 2.0944f; v[k] = { cx + r * std::cos(ang), cy + r * std::sin(ang), 0.5f, 1.0f, col }; }
}


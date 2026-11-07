#!/usr/bin/env bash
# Build dxprobe32.exe / dxprobe64.exe with mingw-w64 (posix threads). Ubuntu: apt install g++-mingw-w64-x86-64-posix g++-mingw-w64-i686-posix
cd "$(dirname "$0")"
x86_64-w64-mingw32-g++-posix -O2 -std=c++17 -static -o dxprobe64.exe dxprobe.cpp dxprobe_d3d8.cpp -luuid -ldxguid
i686-w64-mingw32-g++-posix -O2 -std=c++17 -static -o dxprobe32.exe dxprobe.cpp dxprobe_d3d8.cpp -luuid -ldxguid
sha256sum dxprobe32.exe dxprobe64.exe

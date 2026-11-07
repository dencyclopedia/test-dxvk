# test-dxvk: dxvk.dev test lab (temporary, public)

Temporary public repository that runs the hands-on tests behind dxvk.dev on throwaway
GitHub-hosted machines. It will be deleted when the site is finished. Nothing here is
DXVK itself: DXVK is downloaded from the official releases at
https://github.com/doitsujin/dxvk/releases during each run.

| Path | What |
|---|---|
| `apps/dxprobe.cpp`, `apps/dxprobe_d3d8.cpp`, `apps/common.h` | Tiny Direct3D 8 / 9 / 11 test program: draws N triangles with one draw call each, reports which DLL was loaded, what GPU the game sees, frame times |
| `apps/build.sh` | Builds `dxprobe32.exe` / `dxprobe64.exe` with mingw-w64 |
| `scripts/linux_matrix.sh`, `scripts/linux_cases.sh` | Linux + Wine matrix (wined3d vs DXVK 3.1.1 / 2.7.1 / 1.10.3, install methods, HUD, dxvk.conf, failure modes, shader cache, draw-call scaling) |
| `scripts/windows_matrix.ps1` | Windows matrix (native WARP vs DXVK with Mesa lavapipe + Khronos loader) |
| `.github/workflows/lab.yml` | Runs both matrices and commits `results/` |
| `results/<run>/<machine>/<case>/` | `result.json`, `stdout.txt`, `stderr.txt`, DXVK `*.log`, `shot.png` |

Limits: these machines have no GPU. Rendering is done in software (llvmpipe/lavapipe on Linux,
WARP and lavapipe on Windows), so frame rates show relative CPU cost only and must never be
published as game performance. Real-hardware tests are done by hand (see the dxvk.dev testing guide).

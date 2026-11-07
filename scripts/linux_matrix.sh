#!/usr/bin/env bash
# dxvk.dev test lab: Linux + Wine matrix.
# Runs dxprobe (apps/) under Wine with Wine's own wined3d and with several DXVK
# releases, in the scenarios listed in CASES below, and stores for each case:
#   results/<run>/<case>/result.json   dxprobe output (+ case metadata)
#   results/<run>/<case>/stderr.txt    Wine + DXVK console output
#   results/<run>/<case>/logs/*.log    DXVK log files (DXVK_LOG_PATH)
#   results/<run>/<case>/shot.png      screenshot of the Xvfb screen while it ran (when SHOT=1)
# Usage: scripts/linux_matrix.sh <dl-dir-with-dxvk-tarballs> <run-id>
# Needs: wine (10.1+), Xvfb on $DISPLAY, Mesa lavapipe (amd64 + i386), ImageMagick.
set -u
DL=${1:?tarball dir}; RUN=${2:?run id}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/results/$RUN; mkdir -p "$OUT"
export WINEDEBUG=-all
APPS=$ROOT/apps
PFX_BASE=${PFX_BASE:-$HOME/pfx-lab}
OVR="d3d8,d3d9,d3d10core,d3d11,dxgi=n,b"

extract() { # version -> dir
  local v=$1 d=$DL/x/dxvk-$1
  [ -d "$d" ] || { mkdir -p "$DL/x"; tar -xzf "$DL/dxvk-$v.tar.gz" -C "$DL/x"; }
  echo "$d"
}

fresh_prefix() { # name -> path (fresh copy of a template prefix, made once)
  local tpl=$PFX_BASE/_template p=$PFX_BASE/$1; mkdir -p "$PFX_BASE"
  if [ ! -d "$tpl" ]; then
    WINEPREFIX=$tpl WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -i >/dev/null 2>&1; WINEPREFIX=$tpl wineserver -w
  fi
  rm -rf "$p"; cp -a "$tpl" "$p"; echo "$p"
}

# run_case <case> <api> <arch 64|32> <frames> <draws> <dxvk-version|none> <method> [ENV=VAL ...]
# methods: none | local (DLLs next to exe + overrides) | local-noovr (DLLs next to exe, no overrides)
#          | prefix (README method: system32/syswow64 + overrides) | local-d3d11only | local-wrongarch
run_case() {
  local name=$1 api=$2 arch=$3 frames=$4 draws=$5 ver=$6 method=$7; shift 7
  local dir=$OUT/$name; rm -rf "$dir"; mkdir -p "$dir/logs" "$dir/game"
  local pfx; pfx=$(fresh_prefix lab)
  cp "$APPS/dxprobe$arch.exe" "$dir/game/"
  local ovr="" src=""
  if [ "$ver" != none ]; then src=$(extract "$ver"); fi
  local sub=x64; [ "$arch" = 32 ] && sub=x32
  case $method in
    none) ;;
    local) cp "$src/$sub/"*.dll "$dir/game/"; ovr=$OVR ;;
    local-noovr) cp "$src/$sub/"*.dll "$dir/game/" ;;
    local-d3d11only) cp "$src/$sub/d3d11.dll" "$dir/game/"; ovr=$OVR ;;
    local-wrongarch) local w=x32; [ "$arch" = 32 ] && w=x64; cp "$src/$w/"*.dll "$dir/game/"; ovr=$OVR ;;
    prefix)
      cp "$src/x64/"*.dll "$pfx/drive_c/windows/system32/"; cp "$src/x32/"*.dll "$pfx/drive_c/windows/syswow64/"
      for d in d3d8 d3d9 d3d10core d3d11 dxgi; do
        WINEPREFIX=$pfx wine reg add 'HKCU\Software\Wine\DllOverrides' /v $d /d native /f >/dev/null 2>&1
      done; WINEPREFIX=$pfx wineserver -w ;;
  esac
  [ -n "${CONF:-}" ] && printf '%b\n' "$CONF" > "$dir/game/dxvk.conf"
  local t0; t0=$(date +%s.%N)
  ( cd "$dir/game" && env WINEPREFIX="$pfx" WINEDLLOVERRIDES="$ovr" DXVK_LOG_PATH='Z:'"$dir/logs" "$@" \
      timeout 180 wine "dxprobe$arch.exe" "$api" "$frames" "$draws" "${HOLD:-0}" > "$dir/stdout.txt" 2> "$dir/stderr.txt" ) &
  local pid=$!
  if [ "${SHOT:-0}" = 1 ]; then sleep "${SHOT_AT:-5}"; import -window root "$dir/shot.png" 2>/dev/null; fi
  wait $pid; local rc=$?
  local t1; t1=$(date +%s.%N)
  WINEPREFIX=$pfx wineserver -k 2>/dev/null
  local res; res=$(grep -h '^{' "$dir/stdout.txt" | tail -1); [ -z "$res" ] && res='{"ok":false,"error":"no output (crash or timeout)"}'
  python3 - "$dir" "$name" "$api" "$arch" "$ver" "$method" "$rc" "$t0" "$t1" "$*" "${CONF:-}" <<'EOF'
import json, sys, os, glob
d, name, api, arch, ver, method, rc, t0, t1, env, conf = sys.argv[1:]
raw = open(os.path.join(d, 'stdout.txt'), errors='replace').read().splitlines()
res = next((json.loads(l) for l in reversed(raw) if l.startswith('{')), {"ok": False, "error": "no output (crash or timeout)"})
err = open(os.path.join(d, 'stderr.txt'), errors='replace').read()
dxvk_lines = [l for l in err.splitlines() if l.startswith(('info:', 'warn:', 'err:'))]
ver_line = next((l for l in dxvk_lines if 'DXVK: v' in l), '')
res.update(case=name, apiRequested=api, archRequested=arch, dxvkVersion=ver, method=method, exitCode=int(rc),
           wallSeconds=round(float(t1) - float(t0), 2), env=env, conf=conf,
           dxvkActive=bool(ver_line), dxvkBanner=ver_line.strip(),
           dxvkErrors=[l for l in dxvk_lines if l.startswith('err:')][:15],
           logFiles=sorted(os.path.basename(p) for p in glob.glob(os.path.join(d, 'logs', '*.log'))))
json.dump(res, open(os.path.join(d, 'result.json'), 'w'), indent=1)
print(f"{name:42s} ok={res.get('ok')} dxvk={res['dxvkActive']} fps={res.get('avgFps')} adapter={res.get('adapter','')[:40]!r} err={res.get('error','')[:60]!r}")
EOF
}

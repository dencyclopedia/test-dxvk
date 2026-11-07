#!/usr/bin/env bash
# Case list for the Linux + Wine matrix. Usage: scripts/linux_cases.sh <dl-dir> <run-id> [group...]
# Groups: base compat hud conf fail cache scale. Default: all.
source "$(dirname "$0")/linux_matrix.sh" "$1" "$2"
shift 2; GROUPS_=${*:-base compat hud conf fail cache scale}
has() { [[ " $GROUPS_ " == *" $1 "* ]]; }
F=300; D=1000   # frames, draws per frame

if has base; then  # every API x arch: wined3d vs DXVK 3.1.1 (DLLs next to the exe)
  for api in d3d9 d3d11 d3d8; do for a in 64 32; do
    run_case "base-wined3d-$api-$a" $api $a $F $D none none
    run_case "base-dxvk311-$api-$a" $api $a $F $D 3.1.1 local
  done; done
fi
if has compat; then  # older releases + install methods
  for v in 2.7.1 1.10.3; do for api in d3d9 d3d11 d3d8; do
    run_case "compat-dxvk${v//./}-$api-64" $api 64 $F $D $v local
  done; done
  run_case "method-prefix-dxvk311-d3d9-32" d3d9 32 $F $D 3.1.1 prefix
  run_case "method-prefix-dxvk311-d3d11-64" d3d11 64 $F $D 3.1.1 prefix
  run_case "method-noovr-dxvk311-d3d11-64" d3d11 64 $F $D 3.1.1 local-noovr
fi
if has hud; then  # screenshots of the HUD presets
  for h in 1 fps,frametimes,gpuload full compiler version,api,devinfo; do
    SHOT=1 HOLD=8 SHOT_AT=6 run_case "hud-$(echo $h | tr , _)-d3d11-64" d3d11 64 60 300 3.1.1 local DXVK_HUD=$h
  done
  SHOT=1 HOLD=8 SHOT_AT=6 run_case "hud-full-d3d9-32" d3d9 32 60 300 3.1.1 local DXVK_HUD=full
  SHOT=1 HOLD=8 SHOT_AT=6 run_case "hud-scale2-d3d9-64" d3d9 64 60 300 3.1.1 local DXVK_HUD=fps,devinfo,scale=2.0
  SHOT=1 HOLD=8 SHOT_AT=6 run_case "shot-wined3d-d3d11-64" d3d11 64 60 300 none none
fi
if has conf; then  # dxvk.conf and DXVK_CONFIG effects that a reader can verify
  CONF='dxvk.maxFrameRate = 60' run_case "conf-maxfps60-file-d3d11-64" d3d11 64 180 300 3.1.1 local
  run_case "conf-maxfps60-env-d3d9-64" d3d9 64 180 300 3.1.1 local DXVK_FRAME_RATE=60
  run_case "conf-maxfps30-dxvkconfig-d3d9-32" d3d9 32 120 300 3.1.1 local "DXVK_CONFIG=d3d9.maxFrameRate=30"
  CONF='d3d9.maxAvailableMemory = 2048' run_case "conf-vram2048-d3d9-32" d3d9 32 30 100 3.1.1 local
  CONF='dxgi.maxDeviceMemory = 4096' run_case "conf-vram4096-d3d11-64" d3d11 64 30 100 3.1.1 local
  CONF='dxgi.customVendorId = 1002\ndxgi.customDeviceId = 73bf' run_case "conf-spoofamd-d3d11-64" d3d11 64 30 100 3.1.1 local
  CONF='d3d9.customVendorId = 10de' run_case "conf-spoofnv-d3d9-64" d3d9 64 30 100 3.1.1 local
  CONF='[dxprobe64.exe]\nd3d11.maxFeatureLevel = 10_1' run_case "conf-perapp-fl101-d3d11-64" d3d11 64 30 100 3.1.1 local
  CONF='[otherGame.exe]\nd3d11.maxFeatureLevel = 10_1' run_case "conf-perapp-other-d3d11-64" d3d11 64 30 100 3.1.1 local
  run_case "conf-configfile-env-d3d11-64" d3d11 64 30 100 3.1.1 local DXVK_CONFIG_FILE=Z:/tmp/none-such.conf
fi
if has fail; then  # failure modes users hit, so we can show the real messages
  run_case "fail-vk13-dxvk311-d3d11-64" d3d11 64 30 100 3.1.1 local MESA_VK_VERSION_OVERRIDE=1.3
  run_case "fail-vk13-dxvk311-d3d9-32" d3d9 32 30 100 3.1.1 local MESA_VK_VERSION_OVERRIDE=1.3
  run_case "fail-vk13-dxvk271-d3d11-64" d3d11 64 30 100 2.7.1 local MESA_VK_VERSION_OVERRIDE=1.3
  run_case "fail-vk12-dxvk271-d3d11-64" d3d11 64 30 100 2.7.1 local MESA_VK_VERSION_OVERRIDE=1.2
  run_case "fail-vk11-dxvk1103-d3d11-64" d3d11 64 30 100 1.10.3 local MESA_VK_VERSION_OVERRIDE=1.1
  run_case "fail-d3d11only-dxvk311-64" d3d11 64 30 100 3.1.1 local-d3d11only
  run_case "fail-wrongarch-dxvk311-d3d9-32" d3d9 32 30 100 3.1.1 local-wrongarch
  run_case "fail-wrongarch-dxvk311-d3d11-64" d3d11 64 30 100 3.1.1 local-wrongarch
  run_case "fail-filter-nomatch-d3d11-64" d3d11 64 30 100 3.1.1 local DXVK_FILTER_DEVICE_NAME=NoSuchGPU
  run_case "fail-filter-match-d3d11-64" d3d11 64 30 100 3.1.1 local DXVK_FILTER_DEVICE_NAME=llvmpipe
  run_case "fail-novulkan-dxvk311-d3d11-64" d3d11 64 30 100 3.1.1 local VK_ICD_FILENAMES=/nonexistent.json VK_DRIVER_FILES=/nonexistent.json
  run_case "fail-novulkan-dxvk311-d3d9-64" d3d9 64 30 100 3.1.1 local VK_ICD_FILENAMES=/nonexistent.json VK_DRIVER_FILES=/nonexistent.json
fi
if has cache; then  # internal shader cache: cold vs warm start, where files go
  C=$OUT/_shadercache; rm -rf "$C"; mkdir -p "$C"
  for i in 1 2 3; do run_case "cache-run$i-d3d11-64" d3d11 64 120 300 3.1.1 local DXVK_SHADER_CACHE_PATH="Z:$C"; done
  ls -la "$C" > "$OUT/cache-run3-d3d11-64/cache-listing.txt" 2>&1
  run_case "cache-off-d3d11-64" d3d11 64 120 300 3.1.1 local DXVK_SHADER_CACHE=0
fi
if has scale; then  # draw-call scaling (CPU-bound software GPU: relative numbers only)
  for d in 100 1000 4000; do
    for v in none 3.1.1; do
      m=local; [ $v = none ] && m=none
      run_case "scale-${v//./}-d3d9-64-$d" d3d9 64 300 $d $v $m
      run_case "scale-${v//./}-d3d11-64-$d" d3d11 64 300 $d $v $m
    done
  done
fi
echo "done: $OUT"

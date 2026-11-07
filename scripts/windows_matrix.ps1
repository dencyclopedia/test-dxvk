# dxvk.dev test lab: Windows matrix (GitHub-hosted windows-2025 / windows-2022 runners).
# These machines have no GPU. Native Direct3D runs on Microsoft's software
# renderer (WARP, "Microsoft Basic Render Driver"). For DXVK we add a software
# Vulkan driver (Mesa lavapipe from mesa-dist-win) and the Khronos Vulkan loader.
# Results go to results/<run>/<machine>/<case>/ (result.json, stdout/stderr, DXVK logs, shot.png).
param([string]$Run = "run-local", [string]$Machine = $env:COMPUTERNAME)
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $Root "results\$Run\$Machine"; New-Item -ItemType Directory -Force $Out | Out-Null
$Dl = Join-Path $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }) "dxvkdl"; New-Item -ItemType Directory -Force $Dl | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Shot($path) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
}

# ---- machine facts
$os = Get-CimInstance Win32_OperatingSystem; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM
@{ machine = $Machine; os = $os.Caption; build = $os.BuildNumber; version = $os.Version; cpu = $cpu.Name; cores = $cpu.NumberOfLogicalProcessors
   ramGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1); gpus = $gpu
   vulkan1InSystem32 = (Test-Path "$env:WINDIR\System32\vulkan-1.dll"); vulkan1InSysWOW64 = (Test-Path "$env:WINDIR\SysWOW64\vulkan-1.dll")
   vulkanDriversKey = (Get-ItemProperty "HKLM:\SOFTWARE\Khronos\Vulkan\Drivers" -ErrorAction SilentlyContinue | Out-String) } |
  ConvertTo-Json -Depth 4 | Set-Content "$Out\machine.json"

# ---- downloads: DXVK releases, Mesa lavapipe for Windows, Vulkan loader
$hdr = @{ "User-Agent" = "dxvk-lab"; "Authorization" = "Bearer $env:GITHUB_TOKEN" }
$dlInfo = @()
foreach ($v in "3.1.1", "2.7.1", "1.10.3") {
  $f = "$Dl\dxvk-$v.tar.gz"
  $t0 = Get-Date; Invoke-WebRequest "https://github.com/doitsujin/dxvk/releases/download/v$v/dxvk-$v.tar.gz" -OutFile $f
  $dlInfo += @{ version = $v; seconds = ((Get-Date) - $t0).TotalSeconds; bytes = (Get-Item $f).Length; sha256 = (Get-FileHash $f).Hash }
  tar -xzf $f -C $Dl
}
$dlInfo | ConvertTo-Json | Set-Content "$Out\downloads.json"
$rel = Invoke-RestMethod "https://api.github.com/repos/pal1000/mesa-dist-win/releases/latest" -Headers $hdr
$asset = $rel.assets | Where-Object { $_.name -match "^mesa3d-.*-release-msvc\.7z$" } | Select-Object -First 1
Invoke-WebRequest $asset.browser_download_url -OutFile "$Dl\mesa.7z"; 7z x "$Dl\mesa.7z" "-o$Dl\mesa" -y | Out-Null
# Khronos Vulkan loader (vulkan-1.dll), pinned: the "latest" component URLs return 404
Invoke-WebRequest "https://sdk.lunarg.com/sdk/download/1.4.328.1/windows/VulkanRT-X64-1.4.328.1-Components.zip" -OutFile "$Dl\vkrt.zip"
Expand-Archive "$Dl\vkrt.zip" "$Dl\vkrt" -Force
$vk64 = Get-ChildItem "$Dl\vkrt" -Recurse -Filter vulkan-1.dll | Where-Object { $_.FullName -match "\\x64\\" } | Select-Object -First 1
$vk32 = Get-ChildItem "$Dl\vkrt" -Recurse -Filter vulkan-1.dll | Where-Object { $_.FullName -match "\\x86\\" } | Select-Object -First 1
$icd64 = Get-ChildItem "$Dl\mesa\x64" -Filter "lvp_icd*.json" | Select-Object -First 1
$icd32 = Get-ChildItem "$Dl\mesa\x86" -Filter "lvp_icd*.json" | Select-Object -First 1
# The Vulkan loader ignores VK_DRIVER_FILES / VK_ICD_FILENAMES in elevated processes (CI runs as admin),
# so the lavapipe ICDs are registered the way a real driver installer does it.
function Register-Lvp { New-Item -Force "HKLM:\SOFTWARE\Khronos\Vulkan\Drivers" | Out-Null; New-Item -Force "HKLM:\SOFTWARE\WOW6432Node\Khronos\Vulkan\Drivers" | Out-Null
  New-ItemProperty -Force "HKLM:\SOFTWARE\Khronos\Vulkan\Drivers" -Name $icd64.FullName -Value 0 -PropertyType DWord | Out-Null
  New-ItemProperty -Force "HKLM:\SOFTWARE\WOW6432Node\Khronos\Vulkan\Drivers" -Name $icd32.FullName -Value 0 -PropertyType DWord | Out-Null }
function Unregister-Lvp { Remove-ItemProperty "HKLM:\SOFTWARE\Khronos\Vulkan\Drivers" -Name $icd64.FullName -ErrorAction SilentlyContinue
  Remove-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Khronos\Vulkan\Drivers" -Name $icd32.FullName -ErrorAction SilentlyContinue }
Register-Lvp
@{ mesa = $rel.tag_name; mesaAsset = $asset.name; vulkan64 = "$vk64"; vulkan32 = "$vk32"; icd64 = "$icd64"; icd32 = "$icd32" } |
  ConvertTo-Json | Set-Content "$Out\vulkan-setup.json"

# ---- one case
# Mode: native (no DXVK) | dxvk (all DLLs next to exe) | d3d11only | wrongarch | novulkan (DXVK but no Vulkan driver)
function Case($name, $api, $arch, $frames, $draws, $ver, $mode, $envs = @{}, $conf = "", $hold = 0, $shotAt = 0) {
  $dir = "$Out\$name"; $game = "$dir\game"; New-Item -ItemType Directory -Force $game | Out-Null
  Copy-Item "$Root\apps\dxprobe$arch.exe" $game
  $sub = if ($arch -eq "32") { "x32" } else { "x64" }; $other = if ($arch -eq "32") { "x64" } else { "x32" }
  $vk = if ($arch -eq "32") { $vk32 } else { $vk64 }; $icd = if ($arch -eq "32") { $icd32 } else { $icd64 }
  if ($mode -ne "native") {
    switch ($mode) {
      "dxvk"      { Copy-Item "$Dl\dxvk-$ver\$sub\*.dll" $game }
      "novulkan"  { Copy-Item "$Dl\dxvk-$ver\$sub\*.dll" $game }
      "d3d11only" { Copy-Item "$Dl\dxvk-$ver\$sub\d3d11.dll" $game }
      "wrongarch" { Copy-Item "$Dl\dxvk-$ver\$other\*.dll" $game }
    }
    if ($mode -ne "novulkan") { Copy-Item $vk.FullName $game; $env:VK_DRIVER_FILES = $icd.FullName; $env:VK_ICD_FILENAMES = $icd.FullName }
  }
  if ($mode -eq "novulkan") { Unregister-Lvp } else { Register-Lvp }
  if ($conf) { Set-Content "$game\dxvk.conf" $conf }
  foreach ($k in $envs.Keys) { Set-Item "env:$k" $envs[$k] }
  $t0 = Get-Date
  $p = Start-Process "$game\dxprobe$arch.exe" -ArgumentList $api, $frames, $draws, $hold -WorkingDirectory $game -PassThru `
       -RedirectStandardOutput "$dir\stdout.txt" -RedirectStandardError "$dir\stderr.txt" -WindowStyle Normal
  if ($shotAt -gt 0) { Start-Sleep -Seconds $shotAt; Shot "$dir\shot.png" }
  if (-not $p.WaitForExit(180000)) { $p.Kill() }
  $wall = ((Get-Date) - $t0).TotalSeconds
  foreach ($k in $envs.Keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
  Remove-Item env:VK_DRIVER_FILES, env:VK_ICD_FILENAMES -ErrorAction SilentlyContinue
  $line = Get-Content "$dir\stdout.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -like "{*" } | Select-Object -Last 1
  $res = if ($line) { $line | ConvertFrom-Json } else { [pscustomobject]@{ ok = $false; error = "no output (crash or timeout)" } }
  $logs = Get-ChildItem $game -Filter *.log -ErrorAction SilentlyContinue
  $banner = ""; $errs = @()
  foreach ($l in $logs) { $c = Get-Content $l.FullName; $banner = ($c | Where-Object { $_ -match "DXVK: v" } | Select-Object -First 1); $errs += ($c | Where-Object { $_ -like "err:*" } | Select-Object -First 10) }
  $res | Add-Member -Force case $name; $res | Add-Member -Force dxvkVersion $ver; $res | Add-Member -Force mode $mode
  $res | Add-Member -Force exitCode $p.ExitCode; $res | Add-Member -Force wallSeconds ([math]::Round($wall, 2))
  $res | Add-Member -Force env ($envs | ConvertTo-Json -Compress); $res | Add-Member -Force conf $conf
  $res | Add-Member -Force dxvkActive ([bool]$banner); $res | Add-Member -Force dxvkBanner "$banner"; $res | Add-Member -Force dxvkErrors $errs
  $res | Add-Member -Force logFiles @($logs | ForEach-Object Name)
  $res | ConvertTo-Json -Depth 4 | Set-Content "$dir\result.json"
  foreach ($l in $logs) { Copy-Item $l.FullName $dir }
  Write-Host ("{0,-40} ok={1} dxvk={2} fps={3} adapter={4} err={5}" -f $name, $res.ok, [bool]$banner, $res.avgFps, $res.adapter, $res.error)
}

# ---- cases
foreach ($api in "d3d9", "d3d11", "d3d8") { foreach ($a in "64", "32") {
  Case "base-native-$api-$a" $api $a 300 1000 "" "native"
  Case "base-dxvk311-$api-$a" $api $a 300 1000 "3.1.1" "dxvk"
} }
foreach ($v in "2.7.1", "1.10.3") { foreach ($api in "d3d9", "d3d11") { Case "compat-dxvk$($v -replace '\.','')-$api-64" $api "64" 300 1000 $v "dxvk" } }
Case "shot-native-d3d11-64" "d3d11" "64" 60 300 "" "native" @{} "" 8 6
Case "hud-full-d3d11-64" "d3d11" "64" 60 300 "3.1.1" "dxvk" @{ DXVK_HUD = "full" } "" 8 6
Case "hud-1-d3d9-32" "d3d9" "32" 60 300 "3.1.1" "dxvk" @{ DXVK_HUD = "1" } "" 8 6
Case "conf-maxfps60-d3d11-64" "d3d11" "64" 180 300 "3.1.1" "dxvk" @{} "dxvk.maxFrameRate = 60"
Case "conf-vram2048-d3d9-32" "d3d9" "32" 30 100 "3.1.1" "dxvk" @{} "d3d9.maxAvailableMemory = 2048"
Case "fail-novulkan-d3d11-64" "d3d11" "64" 30 100 "3.1.1" "novulkan"
Case "fail-novulkan-d3d9-32" "d3d9" "32" 30 100 "3.1.1" "novulkan"
Case "fail-d3d11only-64" "d3d11" "64" 30 100 "3.1.1" "d3d11only"
Case "fail-wrongarch-d3d9-32" "d3d9" "32" 30 100 "3.1.1" "wrongarch"
Case "fail-wrongarch-d3d11-64" "d3d11" "64" 30 100 "3.1.1" "wrongarch"
Case "fail-vk13-dxvk311-d3d11-64" "d3d11" "64" 30 100 "3.1.1" "dxvk" @{ MESA_VK_VERSION_OVERRIDE = "1.3" }
Case "log-path-d3d11-64" "d3d11" "64" 30 100 "3.1.1" "dxvk" @{ DXVK_LOG_LEVEL = "warn" }
# uninstall = delete the DLLs: the same folder must go back to native Direct3D
$u = "$Out\uninstall-d3d11-64"; Case "uninstall-before-d3d11-64" "d3d11" "64" 30 100 "3.1.1" "dxvk"
Remove-Item "$Out\uninstall-before-d3d11-64\game\*.dll"; New-Item -ItemType Directory -Force $u | Out-Null; Copy-Item "$Out\uninstall-before-d3d11-64\game" "$u\game" -Recurse -Force
Push-Location $u\game; $o = & .\dxprobe64.exe d3d11 30 100 0; Pop-Location; Set-Content "$u\stdout.txt" $o
# the shader cache location on Windows (default %LOCALAPPDATA%\dxvk)
Get-ChildItem "$env:LOCALAPPDATA\dxvk" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime |
  ConvertTo-Json | Set-Content "$Out\shader-cache-listing.json"
# drop the game folders (DLL copies) so only evidence is committed
Get-ChildItem $Out -Directory | ForEach-Object { Remove-Item "$($_.FullName)\game\*.dll", "$($_.FullName)\game\*.exe" -ErrorAction SilentlyContinue }
Write-Host "done: $Out"

# Runs your installed Factorio as a headless server with the Zenith bridge mod and Lua UDP enabled.
# The 3D client then connects to it over localhost. No game window opens.
#
#   powershell -ExecutionPolicy Bypass -File server\run-server.ps1
#   powershell -ExecutionPolicy Bypass -File server\run-server.ps1 -Save C:\path\my-base.zip
#
# Console commands (like /f3d-status) can be sent over RCON with tools/rcon.py.
param(
  [string]$Save = "",
  [string]$Factorio = "",
  [int]$UdpPort = 34200,
  [int]$GamePort = 34197,
  [int]$RconPort = 34198
)
$ErrorActionPreference = "Stop"

$here = $PSScriptRoot
$repo = Split-Path $here -Parent
if ($Save -eq "") { $Save = Join-Path $here "saves\world.zip" }
$data = Join-Path $here "data"
$mods = Join-Path $data "mods"

# Look in every Steam library, then the standalone installer's default folder.
if ($Factorio -eq "") {
  $candidates = @()
  $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
  if ($steam) {
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
      foreach ($m in (Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"').Matches) {
        $candidates += Join-Path $m.Groups[1].Value.Replace('\\', '\') "steamapps\common\Factorio\bin\x64\factorio.exe"
      }
    }
  }
  $candidates += "C:\Program Files\Factorio\bin\x64\factorio.exe"
  $Factorio = ($candidates | Where-Object { Test-Path $_ } | Select-Object -First 1)
  if (-not $Factorio) { $Factorio = $candidates[0] }
}

if (-not (Test-Path $Factorio)) {
  Write-Error "Factorio not found at $Factorio. Pass -Factorio 'C:\path\to\factorio.exe'."
}

# Keep the server's settings, logs and mods apart from your normal game, so both can run at once.
# data\saves too: /server-save writes there, and Factorio stops the game if it's missing.
New-Item -ItemType Directory -Force -Path $mods, (Join-Path $data "saves"), (Split-Path $Save -Parent) | Out-Null
$readData = (Resolve-Path (Join-Path (Split-Path $Factorio -Parent) "..\..\data")).Path
@"
[path]
read-data=$readData
write-data=$data
"@ | Set-Content -Encoding ASCII (Join-Path $data "config.ini")

# Link the mod from the repo (a junction needs no admin rights), so edits apply on restart.
$link = Join-Path $mods "factorio-3d-bridge"
if (-not (Test-Path $link)) {
  New-Item -ItemType Junction -Path $link -Target (Join-Path $repo "mod\factorio-3d-bridge") | Out-Null
}

# RCON lets tools/rcon.py send console commands; the password stays in the untracked data folder.
$passwordFile = Join-Path $data "rcon-password.txt"
if (-not (Test-Path $passwordFile)) {
  -join ((48..57) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ }) | Set-Content -Encoding ASCII $passwordFile
}
$rconPassword = (Get-Content $passwordFile -Raw).Trim()

$common = @("--config", (Join-Path $data "config.ini"), "--mod-directory", $mods)

if (-not (Test-Path $Save)) {
  Write-Host "Creating a new map at $Save"
  # factorio.exe is a windowed program, so & wouldn't wait for it: the server would start
  # before the map exists.
  $quoted = ($common + @("--create", $Save)) | ForEach-Object { '"' + $_ + '"' }
  Start-Process -FilePath $Factorio -ArgumentList $quoted -Wait -NoNewWindow
  if (-not (Test-Path $Save)) { Write-Error "Map creation failed; see $data\factorio-current.log" }
}

Write-Host "Starting headless Factorio ($Factorio): 3D client UDP on 127.0.0.1:$UdpPort, game port $GamePort, RCON $RconPort"
& $Factorio @common `
  --start-server $Save `
  --server-settings (Join-Path $here "server-settings.json") `
  --enable-lua-udp $UdpPort `
  --port $GamePort `
  --bind 127.0.0.1 `
  --rcon-bind "127.0.0.1:$RconPort" `
  --rcon-password $rconPassword

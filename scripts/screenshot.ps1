# Captures the R36S screen over SSH and saves it as PNG.
# Usage: scripts/screenshot.ps1 <name> [-HostAlias r36]   -> docs/images/<name>.png
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$HostAlias = 'r36'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$raw = Join-Path $root "out/$Name.raw"
$png = Join-Path $root "docs/images/$Name.png"
New-Item -ItemType Directory -Force (Split-Path $raw), (Split-Path $png) | Out-Null

# 640x480 at 32 bpp, stride 2560 bytes.
& ssh.exe $HostAlias "dd if=/dev/fb0 of=/tmp/screenshot.raw bs=2560 count=480 2>/dev/null"
if ($LASTEXITCODE -ne 0) { throw "framebuffer capture failed ($LASTEXITCODE)" }
& scp.exe -O -q "${HostAlias}:/tmp/screenshot.raw" $raw
if ($LASTEXITCODE -ne 0) { throw "download failed ($LASTEXITCODE)" }
& python (Join-Path $root 'tools/fb2png.py') $raw $png
if ($LASTEXITCODE -ne 0) { throw "conversion failed ($LASTEXITCODE)" }
Remove-Item $raw
"Saved $png"

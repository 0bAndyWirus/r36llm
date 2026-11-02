# Copies the vendor boot partition and the probe harvest from the SD card into vendor/ (gitignored).
# Run after tools/R36LLM-Probe.sh has run once on the stock OS. Required before scripts/deploy.ps1 -Wipe.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$data = (Get-Volume -FileSystemLabel EASYROMS).DriveLetter + ':'
$boot = (Get-Volume -FileSystemLabel BOOT).DriveLetter + ':'
if (-not (Test-Path "$data\r36llm-harvest\probe.txt")) { throw "No probe harvest on $data. Run Ports > R36LLM-Probe on the device first." }

$harvest = Join-Path $root 'vendor/harvest'
$bootOrig = Join-Path $root 'vendor/boot-orig'
New-Item -ItemType Directory -Force $harvest, $bootOrig | Out-Null
Copy-Item "$data\r36llm-harvest\*" $harvest -Force
Get-ChildItem -Force "$boot\" | Where-Object Name -ne 'System Volume Information' |
    Copy-Item -Destination $bootOrig -Recurse -Force
Get-ChildItem $harvest, $bootOrig | Format-Table Directory, Name, Length -AutoSize

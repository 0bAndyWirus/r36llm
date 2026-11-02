# Updates boot files and models on an already booted card (does not flash U-Boot).
# Flash out/bsp/artifacts/r36llm.img for a fresh installation, then boot once
# before copying models so the empty data partition can grow.
# -Wipe retains the legacy BOOT/EASYROMS cleanup path and requires a vendor backup.
param([switch]$Wipe)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Get-Drive([string]$Label) {
    $v = Get-Volume -FileSystemLabel $Label -ErrorAction SilentlyContinue
    if (-not $v -or -not $v.DriveLetter) { throw "Volume '$Label' not found. Insert the SD card." }
    return "$($v.DriveLetter):"
}

$boot = try { Get-Drive 'R36BOOT' } catch { Get-Drive 'BOOT' }
$data = try { Get-Drive 'R36DATA' } catch { Get-Drive 'EASYROMS' }
if (Test-Path "$boot\r36-grow.txt") { throw "Boot this fresh image once before copying files; data growth is still pending." }
foreach ($f in 'out/uInitrd', 'out/rk3326-r36s-linux-gadget.dtb', 'out/boot/logo.bmp',
               'out/bsp/artifacts/Image', 'out/bsp/artifacts/rk3326-r36s-linux.dtb',
               'br2-external/board/r36llm/boot.ini') {
    if (-not (Test-Path (Join-Path $root $f))) { throw "Missing $f. Run scripts/build.ps1 first." }
}

if ($Wipe) {
    foreach ($f in 'vendor/boot-orig/Image', 'vendor/boot-orig/uInitrd', 'vendor/boot-orig/boot.ini',
                   'vendor/boot-orig/rk3326-r36s-linux.dtb', 'vendor/harvest/modules-4.4.189.tar.gz') {
        if (-not (Test-Path (Join-Path $root $f))) { throw "Refusing to wipe: backup file $f is missing." }
    }
    Write-Host "Wiping $data (EASYROMS) and dArkOS leftovers on $boot (BOOT)"
    Get-ChildItem -Force "$data\" | Where-Object Name -ne 'System Volume Information' |
        Remove-Item -Recurse -Force
    foreach ($name in 'dtb', 'SELECT MODEL.bat', 'darkosre_device.log') {
        $p = Join-Path "$boot\" $name
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }
}

Copy-Item (Join-Path $root 'out/uInitrd') "$boot\uInitrd" -Force
Copy-Item (Join-Path $root 'out/rk3326-r36s-linux-gadget.dtb') "$boot\" -Force
Copy-Item (Join-Path $root 'out/bsp/artifacts/Image') "$boot\Image" -Force
Copy-Item (Join-Path $root 'out/bsp/artifacts/rk3326-r36s-linux.dtb') "$boot\rk3326-r36s-linux.dtb" -Force
Copy-Item (Join-Path $root 'br2-external/board/r36llm/boot.ini') "$boot\boot.ini" -Force
Copy-Item (Join-Path $root 'out/boot/*.bmp') "$boot\" -Force

$base = "$data\r36llm"
foreach ($d in 'models', 'logs', 'ssh', 'bin') { New-Item -ItemType Directory -Force "$base\$d" | Out-Null }
foreach ($f in 'config.ini', 'prompts.txt', 'autorun.sh.example') {
    if (-not (Test-Path "$base\$f")) { Copy-Item (Join-Path $root "card/r36llm/$f") "$base\$f" }
}
Get-ChildItem (Join-Path $root 'models') -Filter *.gguf -ErrorAction SilentlyContinue | ForEach-Object {
    $dest = "$base\models\$($_.Name)"
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -ne $_.Length) {
        Write-Host "copy model $($_.Name)"
        Copy-Item $_.FullName $dest -Force
    }
}

Write-Host ''
Write-Host "BOOT:"
Get-ChildItem $boot | Format-Table Name, Length -AutoSize
Write-Host "EASYROMS\r36llm:"
Get-ChildItem -Recurse $base | Format-Table FullName, Length -AutoSize

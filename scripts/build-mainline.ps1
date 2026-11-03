param(
    [string]$Initramfs = "",
    [ValidateRange(1, 64)][int]$Jobs = 6,
    [switch]$UsbHost
)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $Initramfs) { $Initramfs = Join-Path $Repo "out/uInitrd" }
if (-not (Test-Path -LiteralPath $Initramfs -PathType Leaf)) {
    throw "Missing existing Buildroot uInitrd: $Initramfs. Run scripts/build.ps1 -Release first, or supply -Initramfs."
}
$Initramfs = (Resolve-Path -LiteralPath $Initramfs).Path
$UsbHostFlag = if ($UsbHost) { "1" } else { "0" }
& docker build -f (Join-Path $Repo "docker/Dockerfile.mainline") -t r36llm-mainline $Repo
if ($LASTEXITCODE -ne 0) { throw "Mainline builder image failed ($LASTEXITCODE)" }
& docker run --rm -v "${Repo}:/repo" -v "${Initramfs}:/input/uInitrd:ro" `
    -v r36llm-mainline-work:/work -e "JOBS=$Jobs" -e "R36LLM_USB_HOST=$UsbHostFlag" r36llm-mainline `
    bash /repo/scripts/mainline/build.sh /input/uInitrd
if ($LASTEXITCODE -ne 0) { throw "Mainline build failed ($LASTEXITCODE); see out/mainline/logs" }
Write-Host "Experimental image: out/mainline/artifacts/r36llm-mainline.img (offline checks only; not boot-tested)"

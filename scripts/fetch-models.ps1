# Downloads the GGUF models used on the device into models/ (skips files already present).
# Usage: scripts/fetch-models.ps1 [-Small]   (-Small: only the two models that fit a 512 MB unit)
param([switch]$Small)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'models'
New-Item -ItemType Directory -Force $dest | Out-Null

$models = @(
    @{ Repo = 'bartowski/SmolLM2-135M-Instruct-GGUF'; File = 'SmolLM2-135M-Instruct-Q4_0.gguf'; Small = $true }
    @{ Repo = 'prism-ml/Bonsai-1.7B-gguf';            File = 'Bonsai-1.7B-Q1_0.gguf';           Small = $true }
    @{ Repo = 'prism-ml/Ternary-Bonsai-2-2B-gguf';    File = 'Ternary-Bonsai-2-2B-PTQ1_0.gguf'; Small = $false }
    @{ Repo = 'prism-ml/Ternary-Bonsai-1.7B-gguf';    File = 'Ternary-Bonsai-1.7B-PQ2_0.gguf';  Small = $false }
    @{ Repo = 'prism-ml/Bonsai-4B-gguf';              File = 'Bonsai-4B-Q1_0.gguf';             Small = $false }
)

foreach ($m in $models) {
    if ($Small -and -not $m.Small) { continue }
    $out = Join-Path $dest $m.File
    if (Test-Path $out) { "skip  $($m.File)"; continue }
    $url = "https://huggingface.co/$($m.Repo)/resolve/main/$($m.File)"
    "fetch $($m.File)"
    & curl.exe -fL --retry 3 -o "$out.part" $url
    if ($LASTEXITCODE -ne 0) { Remove-Item -ErrorAction SilentlyContinue "$out.part"; throw "download failed: $url" }
    Move-Item "$out.part" $out
}
Get-ChildItem $dest -Filter *.gguf | Format-Table Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB) } } -AutoSize

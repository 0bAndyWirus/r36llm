# Benchmarks every model on the device over SSH and writes a publishable report.
# Usage: scripts/bench.ps1 [-HostAlias r36] [-Threads 4]
# Output: docs/benchmarks.md (summary table) and docs/results/<date>/bench.json (raw llama-bench data).
param(
    [string]$HostAlias = 'r36',
    [int]$Threads = 4
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Device([string]$Command) {
    $out = & ssh.exe -o ConnectTimeout=10 -o LogLevel=ERROR $HostAlias $Command
    if ($LASTEXITCODE -ne 0) { throw "ssh failed ($LASTEXITCODE): $Command" }
    return $out
}

function Get-MemAvailableMB {
    $line = Invoke-Device "grep MemAvailable /proc/meminfo"
    return [math]::Round(([long]($line -replace '\D', '')) / 1024)
}

# Free the RAM held by the chat app; it respawns on the home screen without loading a model.
Invoke-Device "touch /tmp/r36llm.noautoload; killall r36llm 2>/dev/null; sleep 2; true" | Out-Null
try {
    $device = [ordered]@{
        Kernel   = (Invoke-Device "uname -r")
        MemTotal = [math]::Round(([long]((Invoke-Device "grep MemTotal /proc/meminfo") -replace '\D', '')) / 1024)
        Governor = (Invoke-Device "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
        MaxFreq  = [math]::Round([long](Invoke-Device "cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq") / 1000)
        Swap     = (Invoke-Device "awk 'NR>1{s+=`$3} END{print int(s/1024)}' /proc/swaps")
    }
    $files = Invoke-Device "ls /data/r36llm/models/*.gguf" | Sort-Object
    $rows = @()
    $raw = @()
    foreach ($f in $files) {
        $name = Split-Path -Leaf $f
        $sizeMB = [math]::Round([long](Invoke-Device "wc -c < '$f'") / 1MB)
        $before = Get-MemAvailableMB
        Write-Host "bench $name ($sizeMB MB, $before MB available)"
        # Sample the hottest thermal zone once per second while llama-bench runs.
        $sampler = "(while :; do cat /sys/class/thermal/thermal_zone*/temp; sleep 1; done) > /tmp/r36bench.temp & S=`$!"
        $json = Invoke-Device "$sampler; llama-bench -m '$f' -t $Threads -p 64 -n 32 -r 2 -o json 2>/dev/null; R=`$?; kill `$S; exit `$R"
        $peakC = [math]::Round([long](Invoke-Device "sort -n /tmp/r36bench.temp | tail -n 1") / 1000)
        $results = ($json -join "`n") | ConvertFrom-Json
        $raw += $results
        $pp = ($results | Where-Object { $_.n_prompt -gt 0 } | Select-Object -First 1).avg_ts
        $tg = ($results | Where-Object { $_.n_gen -gt 0 } | Select-Object -First 1).avg_ts
        $rows += [pscustomobject]@{
            Model   = $name -replace '\.gguf$', ''
            SizeMB  = $sizeMB
            FreeMB  = $before
            PP      = [math]::Round($pp, 2)
            TG      = [math]::Round($tg, 2)
            # ~0.75 English words per token: how fast the console "talks".
            WPM     = [math]::Round($tg * 0.75 * 60)
            # Time to write a 100-token answer, the length of a short paragraph.
            Seconds = if ($tg -gt 0) { [math]::Round(100 / $tg) } else { $null }
            Fits    = ($tg -ge 0.3)
            PeakC   = $peakC
        }
    }
}
finally {
    Invoke-Device "rm -f /tmp/r36llm.noautoload; killall r36llm 2>/dev/null; true" | Out-Null
}

$date = Get-Date -Format 'yyyy-MM-dd'
$resultDir = Join-Path $root "docs/results/$date"
New-Item -ItemType Directory -Force $resultDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)  # no BOM; GitHub renders it as a stray character
[IO.File]::WriteAllText((Join-Path $resultDir 'bench.json'), ($raw | ConvertTo-Json -Depth 5), $utf8)

$md = @()
$md += '# Benchmarks'
$md += ''
$md += "R36S clone (RK3326, 4x Cortex-A35 @ $($device.MaxFreq) MHz, NEON only, no dotprod), $($device.MemTotal) MB RAM, $($device.Swap) MB swap, Linux $($device.Kernel), governor ``$($device.Governor)``."
$md += "Engine: PrismML llama.cpp fork, CPU only, $Threads threads. ``llama-bench -p 64 -n 32 -r 2``. Measured $date."
$md += ''
$md += '|Model|File MB|RAM free before (MB)|Prompt t/s|Generation t/s|Words/min|100-token answer|Peak temp|Fits|'
$md += '|---|---:|---:|---:|---:|---:|---:|---:|---|'
foreach ($r in $rows) {
    $fits = if ($r.Fits) { 'yes' } else { 'no' }
    $secs = if ($null -ne $r.Seconds) { "$($r.Seconds) s" } else { '-' }
    $md += "|$($r.Model)|$($r.SizeMB)|$($r.FreeMB)|$($r.PP)|$($r.TG)|$($r.WPM)|$secs|$($r.PeakC) $([char]0xB0)C|$fits|"
}
$md += ''
$md += 'Words/min assumes ~0.75 English words per token. "Fits" means generation stays above 0.3 t/s (no swap thrashing). Peak temp is the hottest thermal zone sampled once per second during the run (passive cooling, no fan).'
$md += "Raw data: [results/$date/bench.json](results/$date/bench.json)."
[IO.File]::WriteAllText((Join-Path $root 'docs/benchmarks.md'), ($md -join "`n") + "`n", $utf8)
$rows | Format-Table -AutoSize
"Wrote docs/benchmarks.md"

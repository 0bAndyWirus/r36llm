param([switch]$DeviceAvailable)
$ErrorActionPreference = 'Stop'
if (-not $DeviceAvailable) { throw 'Run only after the orchestrator says device available; pass -DeviceAvailable.' }
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Prefix = '/data/r36llm/opt/vocab-head'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$Results = "/data/r36llm/bench-vocab/$Stamp"
$Upload = "$Prefix.upload-$Stamp"
$Local = Join-Path $Repo 'out/vocab'
$Archive = Join-Path $Local 'device-prefix.tar'
if (-not (Test-Path $Archive)) { throw 'Missing device-prefix.tar; run build-device.sh first.' }
# Refuse to overwrite even an earlier experimental prefix. Installed app libs
# and config are never switched; all benchmark processes use this prefix only.
& ssh r36 "test ! -e '$Prefix' && mkdir -p '$Upload'"
if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare a fresh isolated upload.' }
& scp -O $Archive (Join-Path $Repo 'card/r36llm/output-keep-en-fr.txt') (Join-Path $PSScriptRoot 'bench-device.sh') "r36:${Upload}/"
if ($LASTEXITCODE -ne 0) {
    # Only our three uninstalled upload files are removed; a failed cleanup
    # still cannot block the next uniquely named upload or create $Prefix.
    & ssh r36 "rm -f '$Upload/device-prefix.tar' '$Upload/output-keep-en-fr.txt' '$Upload/bench-device.sh'; rmdir '$Upload'"
    throw 'Device artifact copy failed; no final prefix was installed. Retry the command.'
}
& ssh r36 "test ! -e '$Prefix' && mv '$Upload' '$Prefix' && tar -xf '$Prefix/device-prefix.tar' -C '$Prefix' && rm '$Prefix/device-prefix.tar'"
if ($LASTEXITCODE -ne 0) { throw 'Device prefix extraction failed.' }
& ssh r36 "sh '$Prefix/bench-device.sh' '$Prefix' '$Prefix/output-keep-en-fr.txt' '/data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf' '$Results'"
if ($LASTEXITCODE -ne 0) { throw 'Device AB/BA failed; app/governors were restored by the runner trap.' }
& ssh r36 "tar -cf '$Prefix/results-$Stamp.tar' -C '$Results' ."
if ($LASTEXITCODE -ne 0) { throw 'Cannot archive device evidence.' }
& scp -O "r36:${Prefix}/results-$Stamp.tar" (Join-Path $Local "results-$Stamp.tar")
if ($LASTEXITCODE -ne 0) { throw 'Cannot retrieve device evidence.' }
$Evidence = Join-Path $Local "device-$Stamp"
New-Item -ItemType Directory -Path $Evidence | Out-Null
& tar -xf (Join-Path $Local "results-$Stamp.tar") -C $Evidence
if ($LASTEXITCODE -ne 0) { throw 'Cannot extract device evidence.' }
& python (Join-Path $PSScriptRoot 'summarize.py') --device-results $Evidence
if ($LASTEXITCODE -ne 0) { throw 'Cannot summarize device evidence.' }
Write-Host "Device evidence: $Evidence"

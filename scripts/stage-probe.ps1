# Copies the hardware probe (tools/R36LLM-Probe.sh) and its helpers to the stock card's ports folder.
# Run on the stock ArkOS/dArkOS card, then start Ports > R36LLM-Probe on the device.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$r = (Get-Volume -FileSystemLabel EASYROMS).DriveLetter + ':'
New-Item -ItemType Directory -Force "$r\ports\r36llm" | Out-Null
Copy-Item "$root\br2-external\board\r36llm\overlay\usr\sbin\r36-gadget" "$r\ports\r36llm\r36-gadget"

# The probe authorizes this key for SSH during its optional USB cable test.
$keyFile = Join-Path $root 'keys\authorized_keys'
$pub = if (Test-Path $keyFile) { (Get-Content -Raw $keyFile) -replace "`r", '' } else { '' }
[IO.File]::WriteAllText("$r\ports\r36llm\r36llm.pub", $pub)

Copy-Item "$root\tools\R36LLM-Probe.sh" "$r\ports\R36LLM-Probe.sh"
foreach ($f in "$r\ports\R36LLM-Probe.sh", "$r\ports\r36llm\r36-gadget") {
    if ([IO.File]::ReadAllBytes($f) -contains 13) { throw "$f has CRLF line endings; check .gitattributes / git autocrlf" }
}
"Probe staged on $r\ports. On the device: Ports > R36LLM-Probe."

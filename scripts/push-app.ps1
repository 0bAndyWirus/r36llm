$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
# Dropbear provides SCP, not an SFTP subsystem.
& scp -O (Join-Path $Repo "out/r36llm") r36:/data/r36llm/bin/r36llm.upload
if ($LASTEXITCODE -ne 0) { throw "App upload failed ($LASTEXITCODE)" }
# Rename avoids overwriting an executable that is still running. If bin/r36llm is a
# wrapper script (LD_LIBRARY_PATH=/data/r36llm/lib), update the binary behind it instead.
& ssh r36 "cd /data/r36llm/bin && chmod +x r36llm.upload && if [ -f r36llm ] && head -c 2 r36llm | grep -q '#!' && grep -q LD_LIBRARY_PATH r36llm; then mv -f r36llm.upload r36llm.bin; else mv -f r36llm.upload r36llm; fi && (killall r36llm r36llm.bin 2>/dev/null; true)"
if ($LASTEXITCODE -ne 0) { throw "App restart failed ($LASTEXITCODE)" }
& ssh r36 "tail -n 20 /data/r36llm/logs/app.log"
if ($LASTEXITCODE -ne 0) { throw "Could not read app log ($LASTEXITCODE)" }

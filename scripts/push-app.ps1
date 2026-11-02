$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
# Dropbear provides SCP, not an SFTP subsystem.
& scp -O (Join-Path $Repo "out/r36llm") r36:/data/r36llm/bin/r36llm.new
if ($LASTEXITCODE -ne 0) { throw "App upload failed ($LASTEXITCODE)" }
# Rename avoids overwriting an executable that is still running.
& ssh r36 "chmod +x /data/r36llm/bin/r36llm.new && mv -f /data/r36llm/bin/r36llm.new /data/r36llm/bin/r36llm && killall r36llm"
if ($LASTEXITCODE -ne 0) { throw "App restart failed ($LASTEXITCODE)" }
& ssh r36 "tail -n 20 /data/r36llm/logs/app.log"
if ($LASTEXITCODE -ne 0) { throw "Could not read app log ($LASTEXITCODE)" }

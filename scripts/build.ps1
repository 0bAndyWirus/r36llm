$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
$AuthorizedKeys = Join-Path $Repo "keys/authorized_keys"
if (-not (Test-Path -LiteralPath $AuthorizedKeys)) {
    $SshDir = Join-Path $env:USERPROFILE ".ssh"
    $PrivateKey = Join-Path $SshDir "r36llm"
    $PublicKey = "$PrivateKey.pub"
    if (-not (Test-Path -LiteralPath $PublicKey)) {
        New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
        if (Test-Path -LiteralPath $PrivateKey) {
            $KeyText = & ssh-keygen -y -f $PrivateKey
            if ($LASTEXITCODE -ne 0) { throw "Could not derive SSH public key ($LASTEXITCODE)" }
            Set-Content -LiteralPath $PublicKey -Value $KeyText -Encoding ascii
        } else {
            $Keygen = Start-Process -FilePath ssh-keygen -ArgumentList @(
                "-t", "ed25519", "-N", '""', "-C", "r36llm", "-f", "`"$PrivateKey`""
            ) -NoNewWindow -Wait -PassThru
            if ($Keygen.ExitCode -ne 0) { throw "SSH key generation failed ($($Keygen.ExitCode))" }
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $AuthorizedKeys) | Out-Null
    Copy-Item -LiteralPath $PublicKey -Destination $AuthorizedKeys
}
& docker build -t r36llm-builder (Join-Path $Repo "docker")
if ($LASTEXITCODE -ne 0) { throw "Builder image build failed ($LASTEXITCODE)" }
function Invoke-Buildroot([string[]] $Targets) {
    & docker run --rm -v r36llm-br:/home/br/work -v "${Repo}:/src" r36llm-builder bash /src/scripts/br.sh @Targets
    if ($LASTEXITCODE -ne 0) { throw "Buildroot failed ($LASTEXITCODE): $Targets" }
}
if ($args.Count -eq 0) {
    Invoke-Buildroot @("r36llm_defconfig")
    Invoke-Buildroot @("all")
} else {
    Invoke-Buildroot $args
}

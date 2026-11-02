param([switch]$Release)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
$AuthorizedKeys = Join-Path $Repo "keys/authorized_keys"
if (-not $Release -and -not (Test-Path -LiteralPath $AuthorizedKeys)) {
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
if ($args.Count -eq 0) {
    & docker build -f (Join-Path $Repo "docker/Dockerfile.kernel") -t r36llm-kernel $Repo
    if ($LASTEXITCODE -ne 0) { throw "Kernel builder image failed ($LASTEXITCODE)" }
    if ($env:OS -eq "Windows_NT") {
        # Netfilter exports both xt_DSCP.ko and xt_dscp.ko (and similar pairs).
        # A normal NTFS directory silently overwrites one member of each pair.
        $Modules = Join-Path $Repo "out/bsp/artifacts/modules"
        if (Test-Path -LiteralPath $Modules) { Remove-Item -LiteralPath $Modules -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $Modules | Out-Null
        & fsutil.exe file setCaseSensitiveInfo $Modules enable
        if ($LASTEXITCODE -ne 0) { throw "Cannot enable case-sensitive kernel module export ($LASTEXITCODE)" }
    }
    & docker run --rm -v "${Repo}:/repo" -v r36llm-kernel-work:/work -e JOBS=6 r36llm-kernel bash /repo/scripts/bsp/build-kernel.sh --inside
    if ($LASTEXITCODE -ne 0) { throw "Kernel build failed ($LASTEXITCODE)" }
    & docker build -f (Join-Path $Repo "docker/Dockerfile.uboot") -t r36llm-uboot $Repo
    if ($LASTEXITCODE -ne 0) { throw "U-Boot builder image failed ($LASTEXITCODE)" }
    & docker run --rm -v "${Repo}:/src" r36llm-uboot bash /src/scripts/bsp/build-uboot.sh
    if ($LASTEXITCODE -ne 0) { throw "U-Boot build failed ($LASTEXITCODE)" }
}
& docker build -t r36llm-builder (Join-Path $Repo "docker")
if ($LASTEXITCODE -ne 0) { throw "Builder image build failed ($LASTEXITCODE)" }
# BSP containers run as root; Buildroot publishes the final image as user br.
& docker run --rm --user root -v "${Repo}:/src" r36llm-builder sh -c "mkdir -p /src/out/bsp/artifacts && chown br:br /src/out/bsp/artifacts"
if ($LASTEXITCODE -ne 0) { throw "Artifact directory setup failed ($LASTEXITCODE)" }
function Invoke-Buildroot([string[]] $Targets) {
    $ReleaseFlag = if ($Release) { "1" } else { "0" }
    & docker run --rm -e "R36LLM_RELEASE=$ReleaseFlag" -v r36llm-br:/home/br/work -v "${Repo}:/src" r36llm-builder bash /src/scripts/br.sh @Targets
    if ($LASTEXITCODE -ne 0) { throw "Buildroot failed ($LASTEXITCODE): $Targets" }
}
if ($args.Count -eq 0) {
    Invoke-Buildroot @("r36llm_defconfig")
    Invoke-Buildroot @("all")
} else {
    Invoke-Buildroot $args
}

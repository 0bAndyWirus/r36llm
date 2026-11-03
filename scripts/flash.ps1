<#
.SYNOPSIS
Writes an r36llm image to a removable SD card and verifies every written byte.
.DESCRIPTION
Run from an Administrator PowerShell prompt. All data on the selected disk is
lost. Only USB/SD/MMC disks are eligible; -Force only relaxes the 256 GB limit.
SHA256SUMS beside the input is checked when present. For .img.xz, xz.exe or
7z.exe streams into a temporary image before any disk is changed. Allow enough
free space in TEMP for the decompressed image. Checksums detect corruption, not
an untrusted publisher: obtain the image and manifest from the same release.
.PARAMETER ImagePath
An .img or .img.xz file. Defaults to out/bsp/artifacts/r36llm.img.
.PARAMETER DiskNumber
The disk number shown by Get-Disk. Omit to list eligible disks and select one.
.PARAMETER Force
Permit removable disks of 256 GB or larger. Never bypasses other safety checks.
.PARAMETER TargetPath
TEST ONLY (hidden): a new file directly inside TEMP, never a device or existing
file. Exercises the same aligned write/readback loop without disk access or
administrator rights. Do not use this parameter for flashing.
.EXAMPLE
.\scripts\flash.ps1 -WhatIf
.EXAMPLE
.\scripts\flash.ps1 -ImagePath .\r36llm.img.xz -DiskNumber 2
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ImagePath,
    [ValidateRange(0, 2147483647)][int]$DiskNumber,
    [switch]$Force,
    [Parameter(DontShow = $true)][string]$TargetPath
)
$ErrorActionPreference = 'Stop'

function Get-FlashCandidate {
    param([object[]]$Disks, [switch]$AllowLarge)
    $Disks | Where-Object {
        $_.BusType -in @('SD', 'USB', 'MMC') -and -not $_.IsSystem -and
        -not $_.IsBoot -and $_.Size -gt 0 -and ($AllowLarge -or $_.Size -lt 256000000000)
    }
}

function Test-ImageChecksum {
    param([string]$Path)
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $manifest = Join-Path (Split-Path -Parent $Path) 'SHA256SUMS'
    if (Test-Path -LiteralPath $manifest) {
        $name = [IO.Path]::GetFileName($Path)
        $entries = @(foreach ($line in Get-Content -LiteralPath $manifest) {
            if ($line -match '^([0-9a-fA-F]{64})\s+\*?(?:\./)?(.+)$' -and $Matches[2] -ceq $name) {
                $Matches[1]
            }
        })
        if ($entries.Count -ne 1) { throw "SHA256SUMS must contain exactly one entry for $name." }
        if ($actual -ne $entries[0]) { throw "SHA256SUMS mismatch for $name. Nothing was written." }
        Write-Host "SHA256SUMS verified: $name"
    }
    else { Write-Warning 'No SHA256SUMS beside the image; publisher checksum not verified.' }
    return $actual
}

function Expand-FlashImage {
    param([string]$Path, [string]$Destination)
    $tool = Get-Command xz.exe -ErrorAction SilentlyContinue
    if ($tool) { $arguments = '-d -c -- "' + $Path + '"' }
    else {
        $tool = Get-Command 7z.exe -ErrorAction SilentlyContinue
        if (-not $tool) { throw 'Compressed image: install xz.exe or 7z.exe on PATH, or extract the .img first.' }
        $arguments = 'x -so -bsp0 -- "' + $Path + '"'
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $tool.Source
    $info.Arguments = $arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $output = $null
    try {
        $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        Write-Host 'Decompressing into TEMP before opening a disk...'
        [void]$process.Start()
        $errors = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($output)
        $process.WaitForExit()
        $detail = $errors.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Decompression failed: $detail" }
    }
    finally {
        if ($output) { $output.Dispose() }
        $process.Dispose()
    }
}

function Assert-FlashDisk {
    param([object]$Disk, [switch]$AllowLarge)
    if (-not @(Get-FlashCandidate -Disks @($Disk) -AllowLarge:$AllowLarge).Count) {
        throw 'Refusing disk: it is internal, boot/system, empty, or exceeds the size limit.'
    }
    $partitions = @(Get-Partition -DiskNumber $Disk.Number -ErrorAction Stop)
    if (@($partitions | Where-Object { $_.IsBoot -or $_.IsSystem }).Count) {
        throw 'Refusing a disk with a boot or system partition.'
    }
    $osDisk = Get-Partition -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction Stop | Get-Disk
    if ($osDisk.Number -eq $Disk.Number) { throw 'Refusing the disk hosting Windows.' }
    foreach ($page in Get-CimInstance Win32_PageFileUsage -ErrorAction Stop) {
        if ($page.Name -notmatch '^[A-Za-z]:\\') { throw 'Cannot resolve a pagefile disk safely.' }
        $pageDisk = Get-Partition -DriveLetter $page.Name.Substring(0, 1) -ErrorAction Stop | Get-Disk
        if ($pageDisk.Number -eq $Disk.Number) { throw 'Refusing a disk hosting an active pagefile.' }
    }
    # Include configured pagefiles even if they are not currently active.
    foreach ($page in Get-CimInstance Win32_PageFileSetting -ErrorAction Stop) {
        if ($page.Name -notmatch '^[A-Za-z]:\\') { throw 'Cannot resolve a configured pagefile disk safely.' }
        $pageDisk = Get-Partition -DriveLetter $page.Name.Substring(0, 1) -ErrorAction Stop | Get-Disk
        if ($pageDisk.Number -eq $Disk.Number) { throw 'Refusing a disk hosting a configured pagefile.' }
    }
    $volumes = @($partitions | Get-Volume -ErrorAction Stop)
    # Fail closed if Windows cannot query BitLocker, including locked volumes.
    try {
        $encrypted = @(Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftVolumeEncryption' `
            -ClassName Win32_EncryptableVolume -ErrorAction Stop)
        foreach ($volume in $volumes) {
            foreach ($item in $encrypted) {
                if ($item.DeviceID.TrimEnd('\') -ieq $volume.Path.TrimEnd('\')) {
                    # Read-only query: run it even under -WhatIf, or the preflight fails closed.
                    $status = Invoke-CimMethod -InputObject $item -MethodName GetConversionStatus -ErrorAction Stop -WhatIf:$false -Confirm:$false
                    if ($status.ReturnValue -ne 0 -or $status.ConversionStatus -ne 0 -or $item.ProtectionStatus -ne 0) {
                        throw 'The disk contains a BitLocker volume (or its state is unknown).'
                    }
                }
            }
        }
    }
    catch { throw "Cannot approve this disk: BitLocker safety check failed. $($_.Exception.Message)" }
    return $volumes
}

function Initialize-VolumeLock {
    if ('R36Flash.VolumeLock' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace R36Flash {
    public static class VolumeLock {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(string name, uint access, uint share,
            IntPtr security, uint creation, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(SafeFileHandle handle, uint code,
            IntPtr input, uint inputSize, IntPtr output, uint outputSize,
            out uint returned, IntPtr overlapped);
        public static SafeFileHandle Acquire(string path) {
            var handle = CreateFile(path.TrimEnd('\\'), 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (handle.IsInvalid) {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error, "Cannot open volume " + path);
            }
            uint returned;
            foreach (uint code in new uint[] { 0x00090018, 0x00090020 }) {
                if (!DeviceIoControl(handle, code, IntPtr.Zero, 0, IntPtr.Zero, 0, out returned, IntPtr.Zero)) {
                    int error = Marshal.GetLastWin32Error();
                    handle.Dispose();
                    throw new Win32Exception(error, "Cannot lock/dismount volume " + path);
                }
            }
            return handle;
        }
    }
}
'@
}

function Copy-FlashImage {
    param([IO.Stream]$Source, [string]$Destination, [long]$Length, [int]$SectorSize,
        [string]$ExpectedHash, [switch]$TestFile)
    $bufferSize = 1MB
    if ($Length -le 0 -or $Length % $SectorSize -ne 0 -or $bufferSize % $SectorSize -ne 0) {
        throw "Image length and buffer size must be multiples of the $SectorSize-byte sector size."
    }
    $buffer = New-Object byte[] $bufferSize
    $mode = if ($TestFile) { [IO.FileMode]::CreateNew } else { [IO.FileMode]::Open }
    $target = $null
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $target = New-Object IO.FileStream($Destination, $mode, [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::ReadWrite, $bufferSize, [IO.FileOptions]::WriteThrough)
        [long]$written = 0
        while ($written -lt $Length) {
            $want = [int][Math]::Min($buffer.Length, $Length - $written)
            $count = 0
            while ($count -lt $want) {
                $read = $Source.Read($buffer, $count, $want - $count)
                if ($read -eq 0) { throw 'Unexpected end of image.' }
                $count += $read
            }
            $target.Write($buffer, 0, $count)
            [void]$hash.TransformBlock($buffer, 0, $count, $buffer, 0)
            $written += $count
            Write-Progress -Id 1 -Activity 'Writing image' -Status "$written / $Length bytes" `
                -PercentComplete (100.0 * $written / $Length)
        }
        [void]$hash.TransformFinalBlock($buffer, 0, 0)
        $writtenHash = [BitConverter]::ToString($hash.Hash).Replace('-', '')
        if ($writtenHash -ne $ExpectedHash) { throw 'Source image changed after preflight checksum.' }
        $target.Flush($true)
    }
    finally {
        if ($target) { $target.Dispose() }
        $hash.Dispose()
        Write-Progress -Id 1 -Activity 'Writing image' -Completed
    }
    # Reopen after flushing, so verification does not read FileStream's write buffer.
    $target = [IO.File]::Open($Destination, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        [long]$verified = 0
        while ($verified -lt $Length) {
            $count = $target.Read($buffer, 0, [int][Math]::Min($buffer.Length, $Length - $verified))
            if ($count -eq 0) { throw 'Unexpected end of target during readback.' }
            [void]$hash.TransformBlock($buffer, 0, $count, $buffer, 0)
            $verified += $count
            Write-Progress -Id 2 -Activity 'Verifying readback' -Status "$verified / $Length bytes" `
                -PercentComplete (100.0 * $verified / $Length)
        }
        [void]$hash.TransformFinalBlock($buffer, 0, 0)
        $readHash = [BitConverter]::ToString($hash.Hash).Replace('-', '')
        if ($readHash -ne $ExpectedHash) { throw "Readback SHA256 mismatch: expected $ExpectedHash, got $readHash." }
        Write-Host "Verified $Length bytes; SHA256 $readHash"
    }
    finally {
        $target.Dispose()
        $hash.Dispose()
        Write-Progress -Id 2 -Activity 'Verifying readback' -Completed
    }
}

# Dot-source for pure-function tests without running the command.
if ($MyInvocation.InvocationName -eq '.') { return }
if ($env:OS -ne 'Windows_NT') { throw 'Use this helper on Windows.' }
$testFile = -not [string]::IsNullOrWhiteSpace($TargetPath)
if ($testFile -and $PSBoundParameters.ContainsKey('DiskNumber')) { throw 'TargetPath cannot be combined with DiskNumber.' }
if ($testFile) {
    $TargetPath = [IO.Path]::GetFullPath($TargetPath)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($TargetPath) -ine $tempRoot -or
        (Test-Path -LiteralPath $TargetPath) -or $TargetPath.StartsWith('\\')) {
        throw 'Test-only TargetPath must be a NEW file directly inside the local TEMP directory.'
    }
}
else {
    if (-not $WhatIfPreference) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Open PowerShell as Administrator before flashing. -WhatIf can list disks without elevation.'
        }
    }
    $candidates = @(Get-FlashCandidate -Disks @(Get-Disk) -AllowLarge:$Force)
    if ($candidates.Count -eq 0) { Write-Host 'No eligible removable USB/SD/MMC disks. No disk was opened.'; return }
    $candidates | Select-Object Number, FriendlyName, BusType, Size, LogicalSectorSize | Format-Table -AutoSize
    if (-not $PSBoundParameters.ContainsKey('DiskNumber')) {
        if ($WhatIfPreference) { Write-Host 'Dry run: specify -DiskNumber to preflight a particular card.'; return }
        $selection = Read-Host 'Select the SD card disk number'
        if ($selection -notmatch '^\d+$') { throw 'Invalid disk number.' }
        $DiskNumber = [int]$selection
    }
    $disk = Get-Disk -Number $DiskNumber
    if (-not @($candidates | Where-Object Number -eq $DiskNumber).Count) { throw 'Selected disk is not eligible.' }
    $volumes = @(Assert-FlashDisk -Disk $disk -AllowLarge:$Force)
    if ($disk.IsReadOnly) { throw 'Selected disk is read-only. Nothing was changed.' }
    if ($disk.LogicalSectorSize -ne 512) { throw 'This image requires a disk with 512-byte logical sectors.' }
    $TargetPath = "\\.\PhysicalDrive$DiskNumber"
}

if ([string]::IsNullOrWhiteSpace($ImagePath)) {
    $ImagePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'out/bsp/artifacts/r36llm.img'
}
$ImagePath = (Resolve-Path -LiteralPath $ImagePath).ProviderPath
if ($ImagePath -notmatch '\.img(?:\.xz)?$') { throw 'Choose an .img or .img.xz file.' }
$tempImage = $null
$source = $null
$locks = New-Object 'Collections.Generic.List[IDisposable]'
$restoreOnline = $false
try {
    # Holding the input open for reading prevents replacement or modification during preflight.
    $original = [IO.File]::Open($ImagePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $expected = Test-ImageChecksum -Path $ImagePath
        if ($ImagePath.EndsWith('.xz', [StringComparison]::OrdinalIgnoreCase)) {
            $tempImage = Join-Path ([IO.Path]::GetTempPath()) ("r36llm-" + [guid]::NewGuid().ToString('N') + '.img')
            Expand-FlashImage -Path $ImagePath -Destination $tempImage
            $expected = (Get-FileHash -LiteralPath $tempImage -Algorithm SHA256).Hash
            $source = [IO.File]::OpenRead($tempImage)
        }
        else { $source = $original; $original = $null }
    }
    finally { if ($original) { $original.Dispose() } }
    $sector = if ($testFile) { 512 } else { [int][Math]::Max($disk.LogicalSectorSize, $disk.PhysicalSectorSize) }
    if ($source.Length -le 0 -or $source.Length % $sector -ne 0) { throw "Image length must be a nonzero multiple of $sector bytes." }
    if (-not $testFile -and $source.Length -gt $disk.Size) { throw 'Image is larger than the selected disk.' }
    if (-not $PSCmdlet.ShouldProcess($TargetPath, "ERASE and write $($source.Length) bytes, then verify readback")) { return }
    if (-not $testFile) {
        Write-Warning "ALL DATA on disk $DiskNumber ($($disk.FriendlyName), $($disk.Size) bytes) WILL BE LOST."
        if ((Read-Host "Type disk number $DiskNumber again to erase it") -cne "$DiskNumber") { throw 'Confirmation did not match. Nothing was written.' }
        # Recheck identity and safety after the interactive pause (hot-unplug/replug).
        $fresh = Get-Disk -Number $DiskNumber
        if ($fresh.UniqueId -ne $disk.UniqueId -or $fresh.SerialNumber -ne $disk.SerialNumber -or
            $fresh.Size -ne $disk.Size -or $fresh.Path -ne $disk.Path) { throw 'Disk identity changed. Start again.' }
        $volumes = @(Assert-FlashDisk -Disk $fresh -AllowLarge:$Force)
        Initialize-VolumeLock
        foreach ($volume in $volumes) {
            if (-not $volume.Path) { throw 'Cannot lock a volume with no device path.' }
            $locks.Add([R36Flash.VolumeLock]::Acquire($volume.Path))
        }
        if (-not $fresh.IsOffline) {
            try {
                Set-Disk -Number $DiskNumber -IsOffline $true -ErrorAction Stop
                $restoreOnline = $true
            }
            catch {
                # Some removable readers cannot be offlined. Locked/dismounted volumes
                # remain held until raw write AND readback finish; never force a lock.
                if ($locks.Count -eq 0 -and $volumes.Count -ne 0) { throw }
                Write-Warning 'Reader cannot go offline; all existing volumes remain locked and dismounted.'
            }
        }
    }
    Copy-FlashImage -Source $source -Destination $TargetPath -Length $source.Length `
        -SectorSize $sector -ExpectedHash $expected -TestFile:$testFile
    if (-not $testFile) { Write-Host 'Flash and readback complete. Safely eject the card, then boot once before adding models.' }
}
finally {
    if ($source) { $source.Dispose() }
    foreach ($handle in $locks) { $handle.Dispose() }
    if ($restoreOnline) { Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Continue }
    if ($tempImage -and (Test-Path -LiteralPath $tempImage)) {
        # The decompression preflight creates this scratch file even under -WhatIf.
        Remove-Item -LiteralPath $tempImage -Force -WhatIf:$false -Confirm:$false
    }
}

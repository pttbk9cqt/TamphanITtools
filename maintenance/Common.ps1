$ErrorActionPreference = 'Stop'
$Root = 'C:\IT-MAINTENANCE'
function Write-ITLog {
    param([string]$Message, [string]$File = 'DiskMonitor.log')
    Add-Content -LiteralPath (Join-Path $Root $File) -Value ('{0:yyyy-MM-dd HH:mm:ss} | {1}' -f (Get-Date),$Message) -Encoding UTF8
}
function Send-ITMessage {
    param([string]$Message)
    & "$env:SystemRoot\System32\msg.exe" '*' '/TIME:300' $Message 2>&1 | Out-Null
    $ok = $LASTEXITCODE -eq 0
    Write-ITLog "MSG delivered=$ok | $Message"
    return $ok
}
function Get-DiskBand {
    param([UInt64]$FreeBytes)
    if ($FreeBytes -lt 20GB) { return 'Critical' }
    if ($FreeBytes -le 30GB) { return 'Warning' }
    return 'Normal'
}
function Get-ManagedVolume {
    param($Config)
    $volumes = @(Get-CimInstance Win32_Volume | Where-Object { $_.DeviceID -eq $Config.VolumeGUID })
    if ($volumes.Count -ne 1 -or $null -eq $volumes[0].FreeSpace -or $volumes[0].Capacity -le 0) {
        throw 'Managed D: volume missing, locked, or unreadable.'
    }
    return $volumes[0]
}
function Get-ManagedPartition {
    param($Config)
    $parts = @(Get-Partition | Where-Object { @($_.AccessPaths) -contains $Config.VolumeGUID })
    if ($parts.Count -ne 1) { throw 'Cannot uniquely map volume GUID to a current partition.' }
    $p = $parts[0]
    $disk = Get-Disk -Number $p.DiskNumber
    if ($p.IsBoot -or $p.IsSystem -or $p.DriveLetter -eq 'C' -or $disk.IsOffline -or $disk.IsReadOnly -or $disk.BusType -eq 'USB') {
        throw 'Refusing to modify system, boot, USB, offline or read-only partition.'
    }
    $v = Get-ManagedVolume $Config
    if ($v.BootVolume -or $v.SystemVolume -or $v.PageFilePresent -or $v.DriveType -ne 3) {
        throw 'Refusing to modify boot/system/pagefile/non-fixed volume.'
    }
    if ($v.DriveLetter -and $v.DriveLetter -ne 'D:') { throw 'Managed volume has another drive letter; manual review required.' }
    return $p
}
function Set-ManagedDriveLetter {
    param($Config, [ValidateSet('Remove','Assign')][string]$Operation)
    $v = Get-ManagedVolume $Config
    $p = Get-ManagedPartition $Config
    if ($Operation -eq 'Assign') {
        $other = @(Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq 'D:')
        $otherVolume = @(Get-CimInstance Win32_Volume | Where-Object DriveLetter -eq 'D:')
        if ($v.DriveLetter -eq 'D:') { return }
        if ($other.Count -or $otherVolume.Count -or (Get-PSDrive D -ErrorAction SilentlyContinue)) { throw 'D: is already occupied.' }
        $command = 'assign letter=D'
    } else {
        if (-not $v.DriveLetter) { return }
        if ($v.DriveLetter -ne 'D:') { throw 'Unexpected drive letter.' }
        $command = 'remove letter=D'
    }
    # Re-resolve disk/partition from GUID on EVERY operation, never use cached disk numbers.
    $temp = Join-Path $Root ('diskpart-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    try {
        @("select disk $($p.DiskNumber)","select partition $($p.PartitionNumber)",$command,'exit') | Set-Content -LiteralPath $temp -Encoding ASCII
        $result = & "$env:SystemRoot\System32\diskpart.exe" /s $temp 2>&1
        Write-ITLog "DiskPart $Operation | $($result -join ' | ')"
        Start-Sleep -Seconds 2
        $after = Get-ManagedVolume $Config
        if (($Operation -eq 'Assign' -and $after.DriveLetter -ne 'D:') -or ($Operation -eq 'Remove' -and $after.DriveLetter)) {
            throw 'DiskPart postcondition failed; inspect DiskMonitor.log.'
        }
    } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

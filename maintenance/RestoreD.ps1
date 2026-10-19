# Run as administrator when D: was removed. Temporarily disable monitoring during cleanup.
. "$PSScriptRoot\Common.ps1"
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as administrator.' }
    Stop-ScheduledTask -TaskName 'IT-MAINTENANCE' -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskName 'IT-MAINTENANCE' | Out-Null
    $cfg = Get-Content -LiteralPath "$Root\VolumeInfo.json" -Raw | ConvertFrom-Json
    if (-not $cfg.MonitorD) { throw 'No managed D: configured.' }
    Set-ManagedDriveLetter $cfg Assign
    Write-Host 'D: restored. Clean up data, then run: Enable-ScheduledTask -TaskName IT-MAINTENANCE'
} catch { Write-ITLog "Restore D failed: $($_.Exception.Message)"; Write-Error $_; exit 1 }

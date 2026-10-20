function Invoke-WinUtilOriginalMaintenance {
    <# .SYNOPSIS
        Runs the three original ComputerMaintenance workflows without copy/paste.
    #>
    param([Parameter(Mandatory)][ValidateSet('InstallTasks','RemoveTasks','ExportInventory','InstallMonitor','RemoveMonitor')][string]$Action)

    $ErrorActionPreference = 'Stop'
    $root = 'C:\IT-MAINTENANCE'
    if ($env:SystemDrive -ne 'C:') { throw 'The original scripts require Windows on C:.' }
    if ($Action -eq 'ExportInventory' -and $env:COMPUTERNAME -in @('GET-INFOMATION','IT-MAINTENANCE')) {
        throw 'The computer name conflicts with an original script filename. Rename the computer before exporting reports.'
    }

    if ($Action -in @('RemoveTasks','RemoveMonitor')) {
        $names = if ($Action -eq 'RemoveTasks') { @('IT-SHUTDOWN','IT-CLEAN') } else { @('IT-MAINTENANCE') }
        foreach ($name in $names) {
            $task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
            if ($null -ne $task) {
                if ($task.State -eq 'Running') {
                    Stop-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
                }
                Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false -ErrorAction Stop
            }
            if ($null -ne (Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue)) {
                throw "Task was not removed: $name"
            }
        }
        if ($Action -eq 'RemoveTasks') {
            return 'Removed IT-SHUTDOWN and IT-CLEAN. Installed files and any shutdown countdown already started by Windows were retained.'
        }
        return 'Removed IT-MAINTENANCE. Installed monitoring files and volume configuration were retained.'
    }

    Install-WinUtilOriginalMaintenanceFiles

    if ($Action -eq 'InstallTasks') {
        # Keep the original task actions, times, highest privileges and current-user
        # context. /F makes an explicit reinstall replace either named task.
        foreach ($task in @(
            @{ Name='IT-SHUTDOWN'; Command='C:\Windows\System32\shutdown.exe -s -t 600'; Time='21:30' },
            @{ Name='IT-CLEAN'; Command='C:\IT-MAINTENANCE\CLEANER.bat -s -t 600'; Time='12:30' }
        )) {
            $arguments = "/CREATE /SC DAILY /RL HIGHEST /TN `"$($task.Name)`" /TR `"$($task.Command)`" /ST $($task.Time) /F"
            $result = Start-Process -FilePath "$env:SystemRoot\System32\schtasks.exe" -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            if ($result.ExitCode -ne 0) { throw "Could not create $($task.Name): schtasks exit code $($result.ExitCode)." }
            $created = Get-ScheduledTask -TaskName $task.Name -TaskPath '\' -ErrorAction Stop
            if ($null -eq $created -or $created.State -eq 'Disabled') { throw "Task was not created/enabled: $($task.Name)" }
        }
        return 'Verified IT-SHUTDOWN (daily 21:30, shutdown after 600 seconds) and IT-CLEAN (daily 12:30, original CLEANER.bat).'
    }

    $workerAction = if ($Action -eq 'ExportInventory') { 'Inventory' } else { 'Monitor' }
    $started = Get-Date
    $result = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$root\RunOriginal.ps1`" -Action $workerAction" -Wait -PassThru -WindowStyle Hidden
    if ($result.ExitCode -ne 0) { throw "Original $workerAction workflow returned exit code $($result.ExitCode)." }

    if ($Action -eq 'InstallMonitor') {
        $task = Get-ScheduledTask -TaskName 'IT-MAINTENANCE' -TaskPath '\' -ErrorAction Stop
        if ($null -eq $task -or $task.State -eq 'Disabled') { throw 'IT-MAINTENANCE task was not created/enabled.' }
        if (-not (Test-Path -LiteralPath "$root\IT-MAINTENANCE.ps1" -PathType Leaf) -or -not (Test-Path -LiteralPath "$root\VolumeInfo.json" -PathType Leaf)) {
            throw 'Disk monitoring script or volume configuration is missing.'
        }
        return 'Verified IT-MAINTENANCE: 09:00 and 14:00 Monday-Friday. C:/D:/E: monitoring and original automatic D: hiding/restoration are installed. E: is optional and warnings-only.'
    }

    $csvPath = Join-Path $root "$env:COMPUTERNAME.csv"
    $txtPath = Join-Path $root "$env:COMPUTERNAME.txt"
    # DxDiag can hand off to a second process; verify a fresh, stable report.
    $deadline = (Get-Date).AddMinutes(3)
    $lastLength = -1
    $stable = 0
    do {
        $txt = Get-Item -LiteralPath $txtPath -ErrorAction SilentlyContinue
        if ($txt -and $txt.LastWriteTime -ge $started -and $txt.Length -gt 500 -and $txt.Length -eq $lastLength) { $stable++ } else { $stable = 0 }
        if ($txt) { $lastLength = $txt.Length }
        if ($stable -ge 3) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    $csv = Get-Item -LiteralPath $csvPath -ErrorAction Stop
    if ($csv.LastWriteTime -lt $started -or $csv.Length -eq 0 -or $stable -lt 3) { throw 'New CSV or completed DxDiag report was not produced.' }
    $rows = @(Import-Csv -LiteralPath $csvPath)
    $requiredColumns = @('PhanMem','PhienBan','NhaPhatHanh','NgayCaiDat','LicenseStatus')
    if ($rows.Count -eq 0 -or @($requiredColumns | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name }).Count) {
        throw 'Software CSV is empty or missing expected columns.'
    }
    return "Reports created now (no restart required):`n$csvPath`n$txtPath"
}

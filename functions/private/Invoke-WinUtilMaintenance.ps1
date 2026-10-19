function Invoke-WinUtilMaintenance {
    <# .SYNOPSIS
        Executes an approved maintenance action in the shared background runspace.
    #>
    param(
        [ValidateSet('InstallTasks','RemoveTasks','ExportInventory','InstallMonitor','RemoveMonitor','Accounts','Install','Clean','Monitor','RestoreD','ResumeMonitor','Inventory','CancelShutdown')]
        [string]$Action,
        [hashtable]$Options = @{}
    )
    $ErrorActionPreference = 'Stop'
    if ($Action -in @('InstallTasks','RemoveTasks','ExportInventory','InstallMonitor','RemoveMonitor')) {
        return Invoke-WinUtilOriginalMaintenance -Action $Action
    }
    switch ($Action) {
        'Accounts' {
            Invoke-WinUtilMaintenanceAccounts @Options
            return 'Accounts configured. Save work, restart manually, sign in as the employee, then install maintenance.'
        }
        'Install' {
            Invoke-WinUtilMaintenanceInstall @Options
            return 'Maintenance installed. Review C:\IT-MAINTENANCE\Setup-Warnings.txt. Restart manually to generate inventory reports.'
        }
        'Monitor' {
            $task = Get-ScheduledTask -TaskName 'IT-MAINTENANCE'
            if ($task.State -eq 'Disabled') { throw 'Monitoring is paused. Resume it explicitly after cleanup.' }
            Start-ScheduledTask -TaskName 'IT-MAINTENANCE'
            return 'Disk monitoring requested. Follow its status in Task Scheduler and C:\IT-MAINTENANCE\DiskMonitor.log.'
        }
        'Inventory' {
            Start-ScheduledTask -TaskName 'IT-INVENTORY-ONCE'
            return 'Inventory retry requested. It waits for a later boot; inspect Inventory.log. If the one-time task has already succeeded, open the existing CSV and TXT reports.'
        }
        'ResumeMonitor' {
            Enable-ScheduledTask -TaskName 'IT-MAINTENANCE' | Out-Null
            return 'Disk monitoring enabled.'
        }
        'CancelShutdown' {
            $result = Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList '/a' -Wait -PassThru -WindowStyle Hidden
            if ($result.ExitCode -ne 0) { throw "Shutdown abort returned $($result.ExitCode). There may be no pending countdown." }
            return 'Pending shutdown cancelled; the daily task is unchanged.'
        }
    }

    $file = switch ($Action) {
        'Clean' { 'Cleaner.ps1' }
        'RestoreD' { 'Restore-D.ps1' }
    }
    $path = Join-Path 'C:\IT-MAINTENANCE' $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Install maintenance first.' }
    # Use a separate Windows PowerShell process because standalone worker scripts use exit.
    $result = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$path`"" -Wait -PassThru -WindowStyle Hidden
    if ($result.ExitCode -ne 0) { throw "$file returned exit code $($result.ExitCode)." }
    if ($Action -eq 'RestoreD') { return 'D: restored. Monitoring is paused; clean up the volume before resuming.' }
    return 'Temporary file cleanup finished. See C:\IT-MAINTENANCE\Cleaner.log.'
}

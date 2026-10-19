function Invoke-WPFMaintenance {
    <# .SYNOPSIS
        Reviews and dispatches maintenance actions without blocking the WPF thread.
    #>
    param(
        [ValidateSet('InstallTasks','RemoveTasks','ExportInventory','InstallMonitor','RemoveMonitor','Accounts','Install','NetworkDrives','Clean','Monitor','RestoreD','ResumeMonitor','Inventory','OpenFolder','Tasks','CancelShutdown')]
        [string]$Action,
        [ValidateSet('','WPFToggleMaintenanceTasks','WPFToggleMaintenanceMonitor')]
        [string]$StateToggle = ''
    )

    if ($Action -eq 'Tasks') {
        Start-Process taskschd.msc
        return
    }

    if ($sync.ProcessRunning) {
        Show-WinUtilMessage -Message 'Wait for the current operation to finish.' -Title Maintenance -Icon Warning | Out-Null
        return
    }

    $options = @{}
    try {
        if ($Action -eq 'NetworkDrives') {
            $dialog = New-Object Microsoft.Win32.SaveFileDialog
            $dialog.Title = 'Save network drive transfer tool (run without elevation)'
            $dialog.Filter = 'PowerShell script (*.ps1)|*.ps1'
            $dialog.FileName = '03-O-MANG.ps1'
            if ($dialog.ShowDialog() -ne $true) { return }
            $body = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($sync.configs.maintenanceScripts.NetworkDrives))
            [IO.File]::WriteAllText($dialog.FileName, $body, (New-Object Text.UTF8Encoding($true)))
            Write-WinUtilLog -Component Maintenance -Message "Exported network drive tool to $($dialog.FileName)"
            Show-WinUtilMessage -Title Maintenance -Message "Saved: $($dialog.FileName)`nRun the script in Windows PowerShell WITHOUT Run as administrator. Choose 1 in the old account to export O-MANG.json. Copy the script and JSON together, then choose 2 in each target account. No passwords are exported." | Out-Null
            return
        }
        if ($Action -eq 'OpenFolder') {
            if (-not (Test-Path -LiteralPath 'C:\IT-MAINTENANCE' -PathType Container)) { throw 'Install maintenance first.' }
            Start-Process explorer.exe -ArgumentList 'C:\IT-MAINTENANCE'
            return
        }
        if ($Action -in @('Accounts','Install')) {
            if (-not [Environment]::Is64BitProcess -or $PSVersionTable.PSEdition -ne 'Desktop') {
                throw 'Open WinUtil with 64-bit Windows PowerShell 5.1 (powershell.exe) for account and maintenance setup.'
            }
            $options = Show-WinUtilMaintenanceDialog -Action $Action
            if (-not $options) { return }
        }

        $confirmation = switch ($Action) {
            'InstallTasks' {
                "Install the original files in C:\IT-MAINTENANCE and create/replace IT-SHUTDOWN (daily 21:30, shutdown after 600 seconds) and IT-CLEAN (daily 12:30)?`nCLEANER.bat keeps its original behavior: clears the print queue and deletes temporary, .log/.old and other matching files across the system drive.`nExisting files are backed up. Continue?"
            }
            'RemoveTasks' {
                "Delete IT-SHUTDOWN and IT-CLEAN from Task Scheduler?`nInstalled files and reports in C:\IT-MAINTENANCE will be kept. A shutdown countdown that Windows already started is not cancelled. Continue?"
            }
            'ExportInventory' {
                "Run the original GET-INFOMATION code now and write C:\IT-MAINTENANCE\$env:COMPUTERNAME.csv and .txt?`nExisting reports with these names will be replaced. Software is read for this elevated account and the machine. No restart is required. Continue?"
            }
            'InstallMonitor' {
                "Install/replace the original IT-MAINTENANCE task at 09:00 and 14:00 Monday-Friday?`nC: receives free-space warnings. If D: remains below 20 GB after the original warning and 60-minute wait, its drive letter is automatically removed; it is restored when free space reaches 20 GB. Disk scans/optimization run when both exceed 30 GB.`nD: must be present during installation. Continue?"
            }
            'RemoveMonitor' {
                "Stop any running IT-MAINTENANCE task instance and delete the task from Task Scheduler?`nInstalled scripts, VolumeInfo.json, logs and reports in C:\IT-MAINTENANCE will be kept. Continue?"
            }
            'Accounts' {
                "Configure employee '$($options.EmployeeFullName)' (login: '$($options.EmployeeUserName)', blank derives from full name), restrict direct group memberships to $($options.EmployeeGroup), enable/rename built-in Administrator to '$($options.AdminUserName)', and rename computer to '$($options.NewComputerName)'.`nReset administrator password: $($options.ResetAdminPassword); reset existing employee password: $($options.ResetExistingEmployeePassword); require employee password change: $($options.RequireEmployeePasswordChange).`nPassword resets can affect protected sign-in data. Restart manually afterward. Continue?"
            }
            'Install' {
                "Install maintenance for '$($options.EmployeeUserName)' to C:\IT-MAINTENANCE?`nCleanup: daily 12:30, files older than 7 days. Disk monitor: weekdays 09:00 / 14:00. Inventory: after restart.`nHide D: after warning + 60 min below 20 GB: $($options.HideDWhenCritical).`nDaily shutdown countdown at 21:30: $($options.EnableShutdown).`nRemove bundled apps for ALL users and future profiles: $($options.RemoveBundledApps). Keep OneDrive: $($options.KeepOneDrive). Enable Num Lock: $($options.EnableNumLock).`nSetup is not transactional; inspect the log if it stops. Existing shutdown schedules are kept when that option is unchecked. Continue?"
            }
            'Clean' { 'Delete temporary files older than seven days from Windows Temp and all user Temp folders?' }
            'Monitor' { 'Start the installed disk monitoring task? It can scan/optimize disks and, if enabled at setup, hide D: after a warning and 60 minutes below 20 GB.' }
            'RestoreD' { 'Pause disk monitoring and restore the managed D: drive letter? Monitoring stays disabled until you resume it.' }
            'ResumeMonitor' { 'Re-enable disk monitoring? Free space on D: should be at least 20 GB before resuming.' }
            'Inventory' { 'Retry the installed inventory task? It only exports reports after a restart following installation. A successful task removes itself.' }
            'CancelShutdown' { 'Abort the pending Windows shutdown countdown? The daily shutdown task remains scheduled.' }
        }
        if ((Show-WinUtilMessage -Title Maintenance -Message $confirmation -Button YesNo -Icon Warning) -ne 'Yes') {
            if ($StateToggle) { Invoke-WPFMaintenanceToggle -Name $StateToggle -Refresh }
            return
        }

        if ($Action -eq 'Accounts') {
            $machine = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            if ($machine.PartOfDomain -and $env:COMPUTERNAME -ine $options.NewComputerName) {
                $options.DomainCredential = Get-Credential -Message 'Domain account authorized to rename this computer'
                if (-not $options.DomainCredential) { return }
            }
        }

        Write-WinUtilLog -Component Maintenance -Message "Requested action: $Action"
        $sync.ProcessRunning = $true
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Maintenance: $Action" -Percent 0
        Invoke-WPFRunspace -ArgumentList @{ Action = $Action; Options = $options; StateToggle = $StateToggle } -ScriptBlock {
            param($Request)
            $Action = $Request.Action
            $Options = $Request.Options
            $StateToggle = $Request.StateToggle
            try {
                $message = Invoke-WinUtilMaintenance -Action $Action -Options $Options
                Write-WinUtilLog -Component Maintenance -Message "$Action completed. $message"
                Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Maintenance: $message" -Percent 100
                Invoke-WPFUIThread -ScriptBlock {
                    Show-WinUtilMessage -Title Maintenance -Message $message | Out-Null
                }
            } catch {
                $failure = "$Action failed: $($_.Exception.Message). Earlier steps may have completed; inspect the WinUtil session log and C:\IT-MAINTENANCE logs before retrying."
                Write-WinUtilLog -Component Maintenance -Level ERROR -Message $failure
                Set-WinUtilTweaksProgressIndicator -Visible $true -Label 'Maintenance failed' -Percent 100
                Invoke-WPFUIThread -ScriptBlock {
                    Show-WinUtilMessage -Title Maintenance -Message $failure -Icon Error | Out-Null
                }
            } finally {
                foreach ($value in $Options.Values) {
                    if ($value -is [securestring]) { $value.Dispose() }
                }
                $Options.Clear()
                $sync.ProcessRunning = $false
                if ($StateToggle) {
                    Invoke-WPFUIThread -ScriptBlock {
                        Invoke-WPFMaintenanceToggle -Name $StateToggle -Refresh
                    }
                }
            }
        } | Out-Null
        # The worker owns the settings and disposes its secure strings after completion.
        $options = $null
    } catch {
        $sync.ProcessRunning = $false
        Write-WinUtilLog -Component Maintenance -Level ERROR -Message "$Action failed: $($_.Exception.Message)"
        Show-WinUtilMessage -Title Maintenance -Message $_.Exception.Message -Icon Error | Out-Null
        if ($StateToggle) { Invoke-WPFMaintenanceToggle -Name $StateToggle -Refresh }
    } finally {
        if ($options) {
            foreach ($value in $options.Values) {
                if ($value -is [securestring]) { $value.Dispose() }
            }
            $options.Clear()
        }
    }
}

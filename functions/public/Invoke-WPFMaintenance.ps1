function Invoke-WPFMaintenance {
    <# .SYNOPSIS
        Reviews and dispatches maintenance actions without blocking the WPF thread.
    #>
    param(
        [ValidateSet('InstallTasks','RemoveTasks','ExportInventory','InstallMonitor','RemoveMonitor','Tasks','RestartExplorer')]
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

    try {
        $confirmation = switch ($Action) {
            'RestartExplorer' {
                'Restart Windows Explorer in this session? The taskbar and open File Explorer windows will briefly close. Continue?'
            }
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
                "Install/replace the original IT-MAINTENANCE task at 09:00 and 14:00 Monday-Friday?`nC: and E: receive free-space warnings (E: is optional and is never hidden). If D: remains below 20 GB after the original warning and 60-minute wait, its drive letter is automatically removed; it is restored when free space reaches 20 GB. Disk scans/optimization run when both exceed 30 GB.`nD: must be present during installation. Continue?"
            }
            'RemoveMonitor' {
                "Stop any running IT-MAINTENANCE task instance and delete the task from Task Scheduler?`nInstalled scripts, VolumeInfo.json, logs and reports in C:\IT-MAINTENANCE will be kept. Continue?"
            }
        }
        if ((Show-WinUtilMessage -Title Maintenance -Message $confirmation -Button YesNo -Icon Warning) -ne 'Yes') {
            if ($StateToggle) { Invoke-WPFMaintenanceToggle -Name $StateToggle -Refresh }
            return
        }

        Write-WinUtilLog -Component Maintenance -Message "Requested action: $Action"
        $operation = [hashtable]::Synchronized(@{
            Message = ''; Failed = $false; StateToggle = $StateToggle
            ToggleState = $null; StateError = $null
        })
        # Create the delegate on the UI runspace. Workers must not synchronously
        # dispatch modal dialogs or run ScheduledTasks queries on the WPF thread.
        $completeAction = [Action[hashtable]]{
            param([hashtable]$completed)
            try {
                if ($completed.StateToggle) {
                    $toggle = $sync[$completed.StateToggle]
                    if ($null -ne $toggle) {
                        if ($completed.StateError) {
                            $toggle.IsEnabled = $false
                            $toggle.ToolTip = 'Unable to read Scheduled Task status. Reopen WinUtil to try again.'
                        } else {
                            $toggle.IsChecked = $completed.ToggleState
                            $toggle.Tag = $completed.ToggleState
                            $toggle.IsEnabled = $true
                        }
                    }
                }
                $label = if ($completed.Failed) { 'Maintenance failed' } else { "Maintenance: $($completed.Message)" }
                Set-WinUtilTweaksProgressIndicator -Visible $true -Label $label -Percent 100
            } finally {
                $sync.ProcessRunning = $false
            }
            $icon = if ($completed.Failed) { 'Error' } else { 'Information' }
            Show-WinUtilMessage -Title Maintenance -Message $completed.Message -Icon $icon | Out-Null
            Restore-WPFMaintenanceWindow
        }
        $sync.ProcessRunning = $true
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Maintenance: $Action" -Percent 0
        Invoke-WPFRunspace -ArgumentList @{ Action = $Action; Operation = $operation; CompleteAction = $completeAction } -ScriptBlock {
            param($Request)
            $Action = $Request.Action
            $operation = $Request.Operation
            try {
                $message = Invoke-WinUtilMaintenance -Action $Action
                Write-WinUtilLog -Component Maintenance -Message "$Action completed. $message"
                $operation.Message = $message
            } catch {
                $failure = "$Action failed: $($_.Exception.Message). Earlier steps may have completed; inspect the WinUtil session log and C:\IT-MAINTENANCE logs before retrying."
                Write-WinUtilLog -Component Maintenance -Level ERROR -Message $failure
                $operation.Message = $failure
                $operation.Failed = $true
            } finally {
                if ($operation.StateToggle) {
                    try {
                        $operation.ToggleState = Get-WinUtilOriginalMaintenanceStatus -Status $sync.configs.maintenance.($operation.StateToggle).Status
                    } catch {
                        $operation.StateError = $_.Exception.Message
                        Write-WinUtilLog -Component Maintenance -Level ERROR -Message "Unable to refresh task status: $($operation.StateError)"
                    }
                }
                if ($sync.Form -and $sync.Form.Dispatcher) {
                    $sync.Form.Dispatcher.BeginInvoke($Request.CompleteAction, [object[]]@($operation)) | Out-Null
                } else {
                    $Request.CompleteAction.Invoke($operation)
                }
            }
        } | Out-Null
    } catch {
        $sync.ProcessRunning = $false
        Write-WinUtilLog -Component Maintenance -Level ERROR -Message "$Action failed: $($_.Exception.Message)"
        Show-WinUtilMessage -Title Maintenance -Message $_.Exception.Message -Icon Error | Out-Null
        if ($StateToggle) { Invoke-WPFMaintenanceToggle -Name $StateToggle -Refresh }
    }
}

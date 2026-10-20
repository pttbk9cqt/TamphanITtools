function Invoke-WPFRepairWindowsUpdate {
    <# .SYNOPSIS
        Confirms and dispatches cache repair off the WPF thread.
    #>
    if ($sync.ProcessRunning -or $sync.WindowsUpdateRunning) {
        Show-WinUtilMessage -Title 'Repair Windows Update' -Message 'Wait for the current operation to finish.' -Icon Warning | Out-Null
        return
    }
    $message = "Do not continue while Windows is installing updates. This repair stops BITS, Windows Update and Cryptographic Services, renames SoftwareDistribution and catroot2 as backups, then starts services again. Downloaded updates will need to download again. Local update history may be rebuilt; installed updates are not uninstalled.`nIf updates are disabled, this also restores Windows Update defaults and enables updates. Organizational policies may still apply.`nNo Safe Mode or automatic restart. Continue?"
    if ((Show-WinUtilMessage -Title 'Repair Windows Update' -Message $message -Button YesNo -Icon Warning) -ne 'Yes') { return }
    $operation = [hashtable]::Synchronized(@{ Failed = $false; Message = ''; State = $null; StateError = $null })
    $completeAction = [Action[hashtable]]{
        param([hashtable]$completed)
        try {
            foreach ($name in 'WPFToggleWindowsUpdate','WPFToggleMaintenanceWindowsUpdate') {
                if ($sync[$name]) {
                    $sync[$name].IsEnabled = -not [bool]$completed.StateError
                    if (-not $completed.StateError) {
                        $sync[$name].IsChecked = $completed.State
                        $sync[$name].Tag = $completed.State
                    } else {
                        $sync[$name].ToolTip = 'Unable to read update state. Reopen WinUtil to try again.'
                    }
                }
            }
            if ($sync.WPFRepairWindowsUpdate) { $sync.WPFRepairWindowsUpdate.IsEnabled = $true }
            $label = if ($completed.Failed) { 'Windows Update repair failed' } else { 'Windows Update cache reset completed' }
            Set-WinUtilTweaksProgressIndicator -Visible $true -Label $label -Percent 100
        } finally {
            $sync.WindowsUpdateRunning = $false
            $sync.ProcessRunning = $false
        }
        $icon = if ($completed.Failed) { 'Error' } else { 'Information' }
        Show-WinUtilMessage -Title 'Repair Windows Update' -Message $completed.Message -Icon $icon | Out-Null
    }
    $sync.ProcessRunning = $true
    $sync.WindowsUpdateRunning = $true
    foreach ($name in 'WPFToggleWindowsUpdate','WPFToggleMaintenanceWindowsUpdate','WPFRepairWindowsUpdate') {
        if ($sync[$name]) { $sync[$name].IsEnabled = $false }
    }
    try {
        Write-WinUtilLog -Component Updates -Message 'Windows Update cache repair requested and confirmed.'
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label 'Windows Update: repairing cache (please wait)' -Percent 0
        Invoke-WPFRunspace -ArgumentList @{ Operation = $operation; CompleteAction = $completeAction } -ScriptBlock {
            param($Request)
            $operation = $Request.Operation
            try {
                $operation.Message = Repair-WinUtilWindowsUpdate
                Write-WinUtilLog -Component Updates -Message $operation.Message
            } catch {
                $operation.Failed = $true
                $operation.Message = $_.Exception.Message
                Write-WinUtilLog -Component Updates -Level ERROR -Message $operation.Message
            } finally {
                try { $operation.State = Get-WinUtilWindowsUpdateStatus } catch {
                    $operation.StateError = $_.Exception.Message
                    $operation.Message += "`nUnable to refresh update state: $($operation.StateError)"
                }
                if ($sync.Form -and $sync.Form.Dispatcher) {
                    $sync.Form.Dispatcher.BeginInvoke($Request.CompleteAction, [object[]]@($operation)) | Out-Null
                } else { $Request.CompleteAction.Invoke($operation) }
            }
        } | Out-Null
    } catch {
        $operation.Failed = $true
        $operation.StateError = $_.Exception.Message
        $operation.Message = "Unable to start repair: $($_.Exception.Message)"
        Write-WinUtilLog -Component Updates -Level ERROR -Message $operation.Message
        $completeAction.Invoke($operation)
    }
}

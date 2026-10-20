function Invoke-WPFWindowsUpdate {
    <# .SYNOPSIS
        Applies or refreshes the Update tab Windows Update switch.
    #>
    param(
        [switch]$Refresh,
        [ValidateSet('WPFToggleWindowsUpdate','WPFToggleMaintenanceWindowsUpdate')]
        [string]$Name = 'WPFToggleWindowsUpdate'
    )

    $toggle = $sync[$Name]
    if ($null -eq $toggle) { return }

    $ErrorActionPreference = "Stop"
    if ($Refresh -and $sync.WindowsUpdateRunning) {
        $toggle.IsEnabled = $false
        return
    }
    if ($sync.ProcessRunning -and -not $Refresh) {
        $toggle.IsChecked = $toggle.Tag
        Show-WinUtilMessage -Title "Windows Update" -Message "Wait for the current operation to finish." -Icon Warning | Out-Null
        return
    }

    $enable = [bool]$toggle.IsChecked
    if (-not $Refresh -and -not $enable) {
        $confirmation = Show-WinUtilMessage `
            -Message "Disabling Windows Update stops update services, disables scheduled tasks, and clears downloaded update files. Security updates will not be installed until defaults are restored. Continue?" `
            -Title "Disable Windows Update?" `
            -Button "YesNo" `
            -Icon "Warning"
        if ($confirmation -ne 'Yes') {
            $toggle.IsChecked = $toggle.Tag
            return
        }
    }

    try {
        $operation = [hashtable]::Synchronized(@{
            Refresh = [bool]$Refresh
            OwnsBusy = -not $sync.ProcessRunning
            Failed = $false
            Message = ''
            State = $null
            StateError = $null
        })
        # Create the callback on the UI runspace. No service queries or synchronous
        # worker-to-UI dispatch belong in completion, including initial refresh.
        $completeAction = [Action[hashtable]]{
            param([hashtable]$completed)
            try {
                foreach ($controlName in @('WPFToggleWindowsUpdate','WPFToggleMaintenanceWindowsUpdate')) {
                    $control = $sync[$controlName]
                    if ($null -eq $control) { continue }
                    if ($completed.StateError) {
                        $control.IsEnabled = $false
                        $control.ToolTip = "Unable to read Windows Update status. Reopen WinUtil to try again."
                    } else {
                        $control.IsChecked = $completed.State
                        $control.Tag = $completed.State
                        $control.IsEnabled = $true
                    }
                }
                if (-not $completed.Refresh) {
                    $label = if ($completed.Failed) { "Windows Update failed" } elseif ($completed.StateError) { "Windows Update state unavailable" } else { "Windows Update setting applied" }
                    Set-WinUtilTweaksProgressIndicator -Visible $true -Label $label -Percent 100
                }
            } finally {
                $sync.WindowsUpdateRunning = $false
                if ($completed.OwnsBusy) { $sync.ProcessRunning = $false }
            }
            if ($completed.Failed) {
                Show-WinUtilMessage -Title "Windows Update" -Message $completed.Message -Icon Error | Out-Null
            }
        }
        $sync.ProcessRunning = $true
        $sync.WindowsUpdateRunning = $true
        foreach ($controlName in @('WPFToggleWindowsUpdate','WPFToggleMaintenanceWindowsUpdate')) {
            if ($sync[$controlName]) { $sync[$controlName].IsEnabled = $false }
        }
        if (-not $Refresh) {
            Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Windows Update: applying setting" -Percent 0
        }
        Invoke-WPFRunspace -ArgumentList @{ Enable = $enable; Operation = $operation; CompleteAction = $completeAction } -ScriptBlock {
            param($Request)
            $ErrorActionPreference = 'Stop'
            $operation = $Request.Operation
            try {
                if (-not $operation.Refresh) {
                    if ($Request.Enable) {
                        Invoke-WPFUpdatesdefault | Out-Null
                    } else {
                        Invoke-WPFUpdatesdisable -SkipConfirmation | Out-Null
                    }
                    Write-WinUtilLog -Component "Updates" -Message "Windows Update switch completed. Enabled: $($Request.Enable)"
                }
            } catch {
                $operation.Failed = $true
                $operation.Message = "Windows Update switch failed: $($_.Exception.Message)"
                Write-WinUtilLog -Component "Updates" -Level ERROR -Message $operation.Message
            } finally {
                try {
                    $operation.State = Get-WinUtilWindowsUpdateStatus
                } catch {
                    $operation.StateError = $_.Exception.Message
                    Write-WinUtilLog -Component "Updates" -Level ERROR -Message "Unable to read Windows Update status: $($operation.StateError)"
                }
                if ($sync.Form -and $sync.Form.Dispatcher) {
                    $sync.Form.Dispatcher.BeginInvoke($Request.CompleteAction, [object[]]@($operation)) | Out-Null
                } else {
                    $Request.CompleteAction.Invoke($operation)
                }
            }
        } | Out-Null
    } catch {
        $sync.WindowsUpdateRunning = $false
        if ($operation.OwnsBusy) { $sync.ProcessRunning = $false }
        foreach ($controlName in @('WPFToggleWindowsUpdate','WPFToggleMaintenanceWindowsUpdate')) {
            if ($sync[$controlName]) {
                $sync[$controlName].IsEnabled = $true
                $sync[$controlName].IsChecked = $sync[$controlName].Tag
            }
        }
        Write-WinUtilLog -Component "Updates" -Level ERROR -Message "Windows Update switch failed: $($_.Exception.Message)"
        Show-WinUtilMessage -Title "Windows Update" -Message $_.Exception.Message -Icon Error | Out-Null
    }
}

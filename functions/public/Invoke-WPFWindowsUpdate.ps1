function Invoke-WPFWindowsUpdate {
    <# .SYNOPSIS
        Applies or refreshes the Maintenance Windows Update switch.
    #>
    param([switch]$Refresh)

    $toggle = $sync.WPFToggleWindowsUpdate
    if ($null -eq $toggle) { return }

    $ErrorActionPreference = "Stop"
    if ($Refresh) {
        try {
            $toggle.IsChecked = Get-WinUtilWindowsUpdateStatus
            $toggle.Tag = $toggle.IsChecked
            $toggle.IsEnabled = $true
        } catch {
            $toggle.IsEnabled = $false
            $toggle.ToolTip = "Unable to read Windows Update status. Reopen WinUtil to try again."
            Write-WinUtilLog -Component "Updates" -Level ERROR -Message "Unable to read Windows Update status: $($_.Exception.Message)"
        }
        return
    }

    if ($sync.ProcessRunning) {
        $toggle.IsChecked = $toggle.Tag
        Show-WinUtilMessage -Title "Windows Update" -Message "Wait for the current operation to finish." -Icon Warning | Out-Null
        return
    }

    $enable = [bool]$toggle.IsChecked
    if (-not $enable) {
        $confirmation = Show-WinUtilMessage `
            -Message "Disabling Windows Update stops update services, disables scheduled tasks, and clears downloaded update files. Security updates will not be installed until defaults are restored. Continue?" `
            -Title "Disable Windows Update?" `
            -Button "YesNo" `
            -Icon "Warning"
        if ($confirmation -ne 'Yes') {
            Invoke-WPFWindowsUpdate -Refresh
            return
        }
    }

    try {
        $sync.ProcessRunning = $true
        $toggle.IsEnabled = $false
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Windows Update: applying setting" -Percent 0
        Invoke-WPFRunspace -ArgumentList @{ Enable = $enable } -ScriptBlock {
            param($Request)
            try {
                if ($Request.Enable) {
                    Invoke-WPFUpdatesdefault | Out-Null
                } else {
                    Invoke-WPFUpdatesdisable -SkipConfirmation | Out-Null
                }
                Write-WinUtilLog -Component "Updates" -Message "Windows Update switch completed. Enabled: $($Request.Enable)"
                Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Windows Update setting applied; restart Windows" -Percent 100
            } catch {
                $failure = "Windows Update switch failed: $($_.Exception.Message)"
                Write-WinUtilLog -Component "Updates" -Level ERROR -Message $failure
                Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Windows Update failed" -Percent 100
                Invoke-WPFUIThread -ScriptBlock {
                    Show-WinUtilMessage -Title "Windows Update" -Message $failure -Icon Error | Out-Null
                }
            } finally {
                $sync.ProcessRunning = $false
                Invoke-WPFUIThread -ScriptBlock {
                    Invoke-WPFWindowsUpdate -Refresh
                }
            }
        } | Out-Null
    } catch {
        $sync.ProcessRunning = $false
        $toggle.IsEnabled = $true
        Write-WinUtilLog -Component "Updates" -Level ERROR -Message "Windows Update switch failed: $($_.Exception.Message)"
        Show-WinUtilMessage -Title "Windows Update" -Message $_.Exception.Message -Icon Error | Out-Null
        Invoke-WPFWindowsUpdate -Refresh
    }
}

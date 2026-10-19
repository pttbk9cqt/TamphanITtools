function Invoke-WPFMaintenanceToggle {
    <# .SYNOPSIS
        Applies or refreshes one stateful switch on the Maintenance tab.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('WPFToggleMaintenanceTasks','WPFToggleMaintenanceMonitor','WPFToggleWindowsUpdate')]
        [string]$Name,
        [switch]$Refresh
    )

    $toggle = $sync[$Name]
    if ($null -eq $toggle) { return }

    if ($Name -eq 'WPFToggleWindowsUpdate') {
        Invoke-WPFWindowsUpdate -Refresh:$Refresh
        return
    }

    if ($Refresh) {
        try {
            $toggle.IsChecked = Get-WinUtilOriginalMaintenanceStatus -Status $sync.configs.maintenance.$Name.Status
            $toggle.Tag = $toggle.IsChecked
            $toggle.IsEnabled = $true
        } catch {
            $toggle.IsEnabled = $false
            $toggle.ToolTip = 'Unable to read Scheduled Task status. Reopen WinUtil to try again.'
            Write-WinUtilLog -Component Maintenance -Level ERROR -Message "Unable to read $Name status: $($_.Exception.Message)"
        }
        return
    }

    if ($sync.ProcessRunning) {
        $toggle.IsChecked = $toggle.Tag
        Show-WinUtilMessage -Title Maintenance -Message 'Wait for the current operation to finish.' -Icon Warning | Out-Null
        return
    }

    $entry = $sync.configs.maintenance.$Name
    $action = if ($toggle.IsChecked) { $entry.ActionOn } else { $entry.ActionOff }
    Invoke-WPFMaintenance -Action $action -StateToggle $Name
}

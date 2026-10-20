function Restore-WPFMaintenanceWindow {
    <# .SYNOPSIS
        Returns focus to Maintenance after its completion dialog closes.
    #>
    if ($null -eq $sync.Form) { return }
    Invoke-WPFTab 'WPFTab5BT'
    if ($sync.Form.WindowState -eq 'Minimized') { $sync.Form.WindowState = 'Normal' }
    $sync.Form.Activate() | Out-Null
    $sync.Form.Focus() | Out-Null
}

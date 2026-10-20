function Invoke-WinUtilMaintenance {
    <# .SYNOPSIS
        Executes an approved maintenance action in the shared background runspace.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('InstallTasks','RemoveTasks','ExportInventory','InstallMonitor','RemoveMonitor')]
        [string]$Action
    )
    return Invoke-WinUtilOriginalMaintenance -Action $Action
}

function Invoke-WinUtilMaintenance {
    <# .SYNOPSIS
        Executes an approved maintenance action in the shared background runspace.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('InstallTasks','RemoveTasks','ExportInventory','InstallMonitor','RemoveMonitor','RestartExplorer')]
        [string]$Action
    )
    if ($Action -eq 'RestartExplorer') {
        Invoke-WinUtilExplorerUpdate -action restart
        return 'Windows Explorer restarted.'
    }
    return Invoke-WinUtilOriginalMaintenance -Action $Action
}

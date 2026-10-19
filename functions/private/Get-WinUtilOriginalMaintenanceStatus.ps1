function Get-WinUtilOriginalMaintenanceStatus {
    <# .SYNOPSIS
        Reads whether the original scheduled maintenance tasks are installed and enabled.
    #>
    param([Parameter(Mandatory)][ValidateSet('Tasks','Monitor')][string]$Status)

    $names = if ($Status -eq 'Tasks') { @('IT-SHUTDOWN','IT-CLEAN') } else { @('IT-MAINTENANCE') }
    foreach ($name in $names) {
        $task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
        if ($null -eq $task -or $task.State -eq 'Disabled') { return $false }
    }
    return $true
}

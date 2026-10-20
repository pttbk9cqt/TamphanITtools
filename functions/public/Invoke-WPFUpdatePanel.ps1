function Invoke-WPFUpdatePanel {
    <# .SYNOPSIS
        Opens an update page without changing update settings.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('WindowsUpdate','StoreDownloads')]
        [string]$Target
    )

    $uri = if ($Target -eq 'WindowsUpdate') { 'ms-settings:windowsupdate' } else { 'ms-windows-store://downloadsandupdates' }
    try {
        Start-Process -FilePath $uri -ErrorAction Stop
    } catch {
        $message = "Unable to open $Target. Check that the application is installed. $($_.Exception.Message)"
        Write-WinUtilLog -Component Updates -Level ERROR -Message $message
        Show-WinUtilMessage -Title Update -Message $message -Icon Error | Out-Null
    }
}

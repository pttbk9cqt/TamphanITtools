function Invoke-WPFMAS {
    <# .SYNOPSIS
        Opens the Microsoft Activation Scripts menu in a separate interactive console.
    #>
    if ($sync.ProcessRunning) {
        Show-WinUtilMessage -Message 'Another process is currently running.' -Title WinUtil -Button OK -Icon Warning | Out-Null
        return
    }

    # Keep the remote script and its interactive child processes outside the WPF runspace.
    # No activation method or unattended activation arguments are selected by WinUtil.
    $command = @'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
function Show-MASLaunchError {
    param([string]$Message)
    Add-Type -AssemblyName PresentationFramework
    [Windows.MessageBox]::Show($Message, 'Microsoft Activation Scripts', 'OK', 'Error') | Out-Null
}
try {
    irm https://get.activated.win | iex
} catch {
    Write-Host ("Unable to launch Microsoft Activation Scripts: " + $_.Exception.Message) -ForegroundColor Red
    Show-MASLaunchError ("Unable to launch Microsoft Activation Scripts: " + $_.Exception.Message + "`nCheck your Internet connection and try Activation again.")
}
'@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $powershellPath = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }

    try {
        Write-WinUtilLog -Component MAS -Message 'Opening Microsoft Activation Scripts from https://get.activated.win using a hidden bootstrap.'
        $process = Start-Process -FilePath $powershellPath -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encodedCommand) -WindowStyle Hidden -PassThru -ErrorAction Stop
        Write-WinUtilLog -Component MAS -Message "MAS console started (PID $($process.Id)). Follow the external menu for its result."
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label 'MAS opened in a separate console' -Percent 100
    } catch {
        $failure = "Unable to open the MAS console: $($_.Exception.Message)"
        Write-WinUtilLog -Component MAS -Level ERROR -Message $failure
        Show-WinUtilMessage -Title 'Microsoft Activation Scripts' -Message $failure -Icon Error | Out-Null
    }
}

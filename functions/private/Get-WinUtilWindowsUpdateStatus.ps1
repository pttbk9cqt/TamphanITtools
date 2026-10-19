function Get-WinUtilWindowsUpdateStatus {
    <# .SYNOPSIS
        Reads whether automatic updates and their services are enabled.
    #>
    $policy = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
    $services = Get-Service -Name BITS, wuauserv, UsoSvc -ErrorAction Stop

    return ($policy.NoAutoUpdate -ne 1 -and @($services | Where-Object { $_.StartType -eq "Disabled" }).Count -eq 0)
}

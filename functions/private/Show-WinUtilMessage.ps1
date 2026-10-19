function Show-WinUtilMessage {
    <#
    .SYNOPSIS
        Shows a WinUtil message box and returns the selected result.
    #>
    param (
        [string]$Message,
        [string]$Title = "Winutil",
        $Button = "OK",
        $Icon = "Information"
    )

    if ($null -ne $sync -and $null -ne $sync.Form) {
        return [System.Windows.MessageBox]::Show($sync.Form, $Message, $Title, $Button, $Icon)
    }
    return [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Icon)
}

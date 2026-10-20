function Invoke-WPFButton {

    <#

    .SYNOPSIS
        Invokes the function associated with the clicked button

    .PARAMETER Button
        The name of the button that was clicked

    #>

    Param ([string]$Button)

    # Use this to get the name of the button
    #[System.Windows.MessageBox]::Show("$Button","Chris Titus Tech's Windows Utility","OK","Info")
    if (-not $sync.ProcessRunning) {
        Set-WinUtilTweaksProgressIndicator -Visible $false
    }

    if ($sync.configs.maintenance.$Button.Action) {
        Invoke-WPFMaintenance -Action $sync.configs.maintenance.$Button.Action
        return
    }

    # Maintenance tools can call a function or open a Windows panel directly.
    $buttonConfig = $sync.configs.maintenance.$Button
    if ($buttonConfig) {

        # If button has a function defined, call it
        if ($buttonConfig.function) {
            $functionName = $buttonConfig.function
            if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                & $functionName
                return
            }
        }

        # If button has InvokeScript defined, execute the scripts
        if ($buttonConfig.InvokeScript -and $buttonConfig.InvokeScript.Count -gt 0) {
            foreach ($script in $buttonConfig.InvokeScript) {
                if (-not [string]::IsNullOrWhiteSpace($script)) {
                    Invoke-Command -ScriptBlock ([scriptblock]::Create($script)) -ErrorAction Stop
                }
            }
            return
        }
    }

    # Other application and navigation buttons use the built-in handlers.
    Switch -Wildcard ($Button) {
        "WPFTab?BT" {
            Invoke-WPFTab $Button
            if ($Button -eq 'WPFTab3BT') {
                Invoke-WPFMAS
            }
        }
        "WPFOpenWindowsUpdate" {Invoke-WPFUpdatePanel -Target WindowsUpdate}
        "WPFOpenStoreDownloads" {Invoke-WPFUpdatePanel -Target StoreDownloads}
        "WPFFixesWinget" {Invoke-WPFFixesWinget}
        "WPFInstall" {Invoke-WPFInstall}
        "WPFUninstall" {Invoke-WPFUnInstall}
        "WPFInstallUpgrade" {Invoke-WPFInstallUpgrade}
        "WPFSelectAllTweaks" {
            $keys = @($sync.configs.tweaks.PSObject.Properties | Where-Object {
                $_.Name -like 'WPFTweaks*' -and (-not $_.Value.Type -or $_.Value.Type -eq 'CheckBox')
            } | ForEach-Object { $_.Name })
            Invoke-WPFPresets -preset $keys -imported $true -checkboxfilterpattern "WPFTweak*"
        }
        "WPFClearTweaksSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFTweak*"}
        "WPFClearInstallSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFInstall*"}
        "WPFtweaksbutton" {Invoke-WPFtweaksbutton}
        "WPFundoall" {Invoke-WPFundoall}
        "WPFGetInstalled" {Invoke-WPFGetInstalled -CheckBox "winget"}
        "WPFInstallSelectedAppx" {Invoke-WPFAppxInstall}
        "WPFRemoveSelectedAppx" {Invoke-WPFAppxRemoval}
        "WPFSelectAllAppx" {
            $sync.configs.appxHashtable.Keys | ForEach-Object {$sync.$_.IsChecked = $true}
        }
        "WPFClearAppxSelection" {
            $sync.configs.appxHashtable.Keys | ForEach-Object {$sync.$_.IsChecked = $false}
        }
        "WPFCloseButton" {$sync.Form.Close(); Write-Host "Bye bye!"}
        "WPFMinimizeButton" {[Windows.SystemCommands]::MinimizeWindow($sync.Form)}
        "WPFMaximizeButton" {
            if ($sync.Form.WindowState -eq [Windows.WindowState]::Normal) {
                [Windows.SystemCommands]::MaximizeWindow($sync.Form)
            } else {
                [Windows.SystemCommands]::RestoreWindow($sync.Form)
            }
        }
    }
}

BeforeAll {
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    . "$script:root/functions/public/Invoke-WPFButton.ps1"
    . "$script:root/functions/private/Restore-WPFMaintenanceWindow.ps1"
    . "$script:root/functions/private/Invoke-WinUtilMaintenance.ps1"
    function Invoke-WPFPresets { param($preset,$imported,$checkboxfilterpattern) }
    function Invoke-WPFTab { param($ClickedTab) }
    function Invoke-WinUtilExplorerUpdate { param($action) }
    function Set-WinUtilTweaksProgressIndicator { param($Visible,$Label,$Percent) }
}

Describe 'Selection cleanup and Maintenance return' {
    It 'selects all checkbox tweaks without applying immediate toggles' {
        $script:sync = @{ configs = @{ tweaks = [pscustomobject]@{
            WPFTweaksOne = [pscustomobject]@{}
            WPFTweaksTwo = [pscustomobject]@{ Type = 'CheckBox' }
            WPFToggleOne = [pscustomobject]@{ Type = 'Toggle' }
        } } }
        Mock Invoke-WPFPresets {}
        Invoke-WPFButton WPFSelectAllTweaks
        Should -Invoke Invoke-WPFPresets -Times 1 -Exactly -ParameterFilter {
            $imported -and $checkboxfilterpattern -eq 'WPFTweak*' -and
            $preset.Count -eq 2 -and $preset -contains 'WPFTweaksOne' -and $preset -contains 'WPFTweaksTwo'
        }
    }

    It 'restores and focuses the Maintenance window' {
        $script:sync = @{ Form = [pscustomobject]@{ WindowState = 'Minimized'; Activated = $false; Focused = $false } }
        $sync.Form | Add-Member ScriptMethod Activate { $this.Activated = $true }
        $sync.Form | Add-Member ScriptMethod Focus { $this.Focused = $true }
        Mock Invoke-WPFTab {}
        Restore-WPFMaintenanceWindow
        Should -Invoke Invoke-WPFTab -Times 1 -Exactly -ParameterFilter { $ClickedTab -eq 'WPFTab5BT' }
        $sync.Form.WindowState | Should -Be Normal
        $sync.Form.Activated | Should -BeTrue
        $sync.Form.Focused | Should -BeTrue
    }

    It 'routes Explorer restart through the existing helper' {
        Mock Invoke-WinUtilExplorerUpdate {}
        Invoke-WinUtilMaintenance RestartExplorer | Should -Be 'Windows Explorer restarted.'
        Should -Invoke Invoke-WinUtilExplorerUpdate -Times 1 -Exactly -ParameterFilter { $action -eq 'restart' }
    }

    It 'removes retired controls and catalog entries' {
        $xaml = Get-Content "$script:root/xaml/inputXML.xaml" -Raw
        foreach ($name in 'WPFstandard','WPFminimal','WPFAdvanced','WPFGetInstalledTweaks','WPFDefaultAppxSelection','WPFGetInstalledAppx') {
            $xaml | Should -Not -Match ('Name="' + $name + '"')
        }
        $xaml.IndexOf('Name="WPFSelectAllTweaks"') | Should -BeLessThan $xaml.IndexOf('Name="WPFClearTweaksSelection"')
        $navigation = Get-Content "$script:root/config/appnavigation.json" -Raw | ConvertFrom-Json
        $navigation.PSObject.Properties.Name | Should -Not -Contain WPFselectedAppsButton
        $tweaks = Get-Content "$script:root/config/tweaks.json" -Raw | ConvertFrom-Json
        foreach ($name in 'WPFToggleDetailedBSoD','WPFToggleLongPaths','WPFToggleNewOutlook','WPFToggleStickyKeys','WPFToggleBatteryPercentage','WPFTweaksDisableIPv6','WPFTweaksIPv46','WPFTweaksRevertStartMenu') {
            $tweaks.PSObject.Properties.Name | Should -Not -Contain $name
        }
    }
}

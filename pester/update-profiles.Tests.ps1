#===========================================================================
# Tests - Windows Update Profiles
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUpdatesdisable.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUpdatesdefault.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFWindowsUpdate.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilWindowsUpdateStatus.ps1")

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    function Invoke-WPFRunspace { param($ArgumentList,$ScriptBlock) }
    function Invoke-WPFUIThread { param($ScriptBlock) & $ScriptBlock }
    function Set-WinUtilTweaksProgressIndicator { param($Visible,$Label,$Percent) }
    function Get-ScheduledTask {
        param($TaskPath, $ErrorAction)
    }
    function Disable-ScheduledTask {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            $ErrorAction
        )
        process { }
    }
    function Enable-ScheduledTask {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            $ErrorAction
        )
        process { }
    }
    function secedit {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            $Arguments
        )
    }

    $script:updateTaskPaths = @(
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'
    )
}

Describe "Get-WinUtilWindowsUpdateStatus" {
    BeforeEach {
        Mock Get-ItemProperty { $null }
        Mock Get-Service {
            @("BITS", "wuauserv", "UsoSvc") | ForEach-Object {
                [pscustomobject]@{ Name = $_; StartType = "Manual"; Status = "Stopped" }
            }
        }
    }

    It "reports enabled when services are available even if not currently running" {
        Get-WinUtilWindowsUpdateStatus | Should -BeTrue
    }

    It "reports disabled when automatic updates are blocked by policy" {
        Mock Get-ItemProperty { [pscustomobject]@{ NoAutoUpdate = 1 } }
        Get-WinUtilWindowsUpdateStatus | Should -BeFalse
    }

    It "reports disabled when <Service> is disabled" -TestCases @(
        @{ Service = "BITS" }
        @{ Service = "wuauserv" }
        @{ Service = "UsoSvc" }
    ) {
        param([string]$Service)
        Mock Get-Service { [pscustomobject]@{ Name = $Service; StartType = "Disabled" } }
        Get-WinUtilWindowsUpdateStatus | Should -BeFalse
    }

    It "propagates unavailable service state instead of reporting enabled" {
        Mock Get-Service { throw "Service query failed" }
        { Get-WinUtilWindowsUpdateStatus } | Should -Throw "Service query failed"
    }
}

Describe "Invoke-WPFWindowsUpdate" {
    BeforeEach {
        $script:updateEnabled = $true
        $script:sync = [hashtable]::Synchronized(@{
            ProcessRunning = $false
            WPFToggleWindowsUpdate = [pscustomobject]@{
                IsChecked = $true
                IsEnabled = $true
                Tag = $true
                ToolTip = "Windows Update"
            }
        })
        Mock Write-WinUtilLog { }
        Mock Show-WinUtilMessage { "Yes" }
        Mock Invoke-WPFRunspace { & $ScriptBlock $ArgumentList }
        Mock Invoke-WPFUIThread { & $ScriptBlock }
        Mock Set-WinUtilTweaksProgressIndicator { }
        Mock Get-WinUtilWindowsUpdateStatus { $script:updateEnabled }
        Mock Invoke-WPFUpdatesdefault { $script:updateEnabled = $true }
        Mock Invoke-WPFUpdatesdisable { $script:updateEnabled = $false }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "refreshes the switch without applying Windows Update changes" {
        $script:updateEnabled = $false
        Invoke-WPFWindowsUpdate -Refresh

        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeFalse
        $sync.WPFToggleWindowsUpdate.Tag | Should -BeFalse
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        Should -Not -Invoke Invoke-WPFUpdatesdisable
        Should -Not -Invoke Invoke-WPFRunspace
    }

    It "restores defaults when switched on" {
        $sync.WPFToggleWindowsUpdate.Tag = $false
        Invoke-WPFWindowsUpdate

        Should -Invoke Invoke-WPFUpdatesdefault -Times 1 -Exactly
        Should -Not -Invoke Invoke-WPFUpdatesdisable
        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeTrue
        $sync.ProcessRunning | Should -BeFalse
    }

    It "disables updates when switched off" {
        $sync.WPFToggleWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate

        Should -Invoke Invoke-WPFUpdatesdisable -Times 1 -Exactly
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeFalse
    }

    It "returns to the actual enabled state when disabling is cancelled" {
        Mock Show-WinUtilMessage { "No" }
        $sync.WPFToggleWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate

        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeTrue
        $sync.WPFToggleWindowsUpdate.Tag | Should -BeTrue
        Should -Not -Invoke Invoke-WPFUpdatesdisable
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        Should -Not -Invoke Invoke-WPFRunspace
    }

    It "preserves the switch and running flag when another operation is active" {
        $sync.ProcessRunning = $true
        $sync.WPFToggleWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate

        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeTrue
        $sync.ProcessRunning | Should -BeTrue
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        Should -Not -Invoke Invoke-WPFUpdatesdisable
    }

    It "reports a failed operation and restores actual state without retrying it" {
        Mock Invoke-WPFUpdatesdisable { throw "Disable failed" }
        $sync.WPFToggleWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate

        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeTrue
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Icon -eq "Error" }
        Should -Invoke Invoke-WPFUpdatesdisable -Times 1 -Exactly
        Should -Not -Invoke Invoke-WPFUpdatesdefault
    }

    It "queues the system work instead of running it on the WPF thread" {
        Mock Invoke-WPFRunspace { }
        $sync.WPFToggleWindowsUpdate.IsChecked = $false

        Invoke-WPFWindowsUpdate

        Should -Invoke Invoke-WPFRunspace -Times 1 -Exactly
        Should -Not -Invoke Invoke-WPFUpdatesdisable
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        $sync.ProcessRunning | Should -BeTrue
        $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeFalse
    }

    It "disables the control when its state cannot be read" {
        Mock Get-WinUtilWindowsUpdateStatus { throw "Service query failed" }
        Invoke-WPFWindowsUpdate -Refresh

        $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeFalse
        $sync.WPFToggleWindowsUpdate.ToolTip | Should -Match "Unable to read"
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        Should -Not -Invoke Invoke-WPFUpdatesdisable
    }
}

Describe "Invoke-WPFUpdatesdisable" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Show-WinUtilMessage { "Yes" }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Set-Service { }
        Mock Stop-Service { }
        Mock Remove-Item { }
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                TaskPath = $TaskPath
            }
        }
        Mock Disable-ScheduledTask { }
    }

    It "sets update disable registry policy values" {
        Invoke-WPFUpdatesdisable

        Should -Invoke -CommandName New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and $Force -eq $true
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUOptions" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -and
                $Name -eq "DODownloadMode" -and
                $Type -eq "DWord" -and
                $Value -eq 0
        }
    }

    It "disables update services and clears the SoftwareDistribution folder" {
        Invoke-WPFUpdatesdisable

        foreach ($expectedServiceName in @("BITS", "wuauserv", "UsoSvc")) {
            $expected = $expectedServiceName
            Should -Invoke -CommandName Stop-Service -Times 1 -Exactly -ParameterFilter {
                $Name -eq $expected -and $Force -eq $true
            }
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "BITS" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Remove-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "C:\Windows\SoftwareDistribution\*" -and
                $Recurse -eq $true -and
                $Force -eq $true
        }
    }

    It "disables update scheduled task paths" {
        Invoke-WPFUpdatesdisable

        foreach ($expectedTaskPath in $script:updateTaskPaths) {
            $expected = $expectedTaskPath
            Should -Invoke -CommandName Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskPath -eq $expected
            }
        }
        Should -Invoke -CommandName Disable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
    }

    It "requires confirmation before disabling updates" {
        Mock Show-WinUtilMessage { "No" }

        Invoke-WPFUpdatesdisable

        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Title -eq "Disable Windows Update?" -and
                $Button -eq "YesNo" -and
                $Icon -eq "Warning"
        }
        Should -Not -Invoke Set-ItemProperty
        Should -Not -Invoke Set-Service
        Should -Not -Invoke Remove-Item
    }
}

Describe "Invoke-WPFUpdatesdefault" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Remove-Item { }
        Mock Remove-ItemProperty { }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                SettingsPageVisibility = "hide:windowsupdate"
            }
        }
        Mock Set-Service { }
        Mock Start-Service { }
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                TaskPath = $TaskPath
            }
        }
        Mock Enable-ScheduledTask { }
        Mock secedit { }
    }

    It "removes only registry values managed by WinUtil" {
        Invoke-WPFUpdatesdefault

        $expectedRegistryValues = @(
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU", "NoAutoUpdate", "AUOptions", "NoAutoRebootWithLoggedOnUsers", "AUPowerManagement"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "ExcludeWUDriversInQualityUpdate", "DeferFeatureUpdates", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdates", "DeferQualityUpdatesPeriodInDays"),
            @("HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings", "BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata", "PreventDeviceMetadataFromNetwork"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching", "DontPromptForWindowsUpdate", "DontSearchWindowsUpdate", "DriverUpdateWizardWuSearchEnabled"),
            @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config", "DODownloadMode")
        )

        foreach ($expectedEntry in $expectedRegistryValues) {
            $expectedPath = $expectedEntry[0]
            foreach ($expectedName in $expectedEntry[1..($expectedEntry.Count - 1)]) {
                $valueName = $expectedName
                Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
                    $Path -eq $expectedPath -and $Name -eq $valueName
                }
            }
        }
        Should -Not -Invoke Remove-Item
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -and
                $Name -eq "SettingsPageVisibility"
        }
    }

    It "preserves unrelated Settings page visibility policy" {
        Mock Get-ItemProperty {
            [pscustomobject]@{
                SettingsPageVisibility = "hide:privacy"
            }
        }

        Invoke-WPFUpdatesdefault

        Should -Not -Invoke Remove-ItemProperty -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -and
                $Name -eq "SettingsPageVisibility"
        }
    }

    It "restores update service startup types" {
        Invoke-WPFUpdatesdefault

        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "BITS" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Start-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc" -and $StartupType -eq "Automatic"
        }
        Should -Not -Invoke Set-Service -ParameterFilter {
            $Name -eq "WaaSMedicSvc"
        }
    }

    It "enables update scheduled task paths without resetting unrelated local security policy" {
        Invoke-WPFUpdatesdefault

        foreach ($expectedTaskPath in $script:updateTaskPaths) {
            $expected = $expectedTaskPath
            Should -Invoke -CommandName Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskPath -eq $expected
            }
        }
        Should -Invoke -CommandName Enable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
        Should -Not -Invoke secedit
    }
}

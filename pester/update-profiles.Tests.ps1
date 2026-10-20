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
        Should -Invoke Invoke-WPFRunspace -Times 1 -Exactly -ParameterFilter { $ArgumentList.Operation.Refresh }
    }

    It "restores defaults when switched on" {
        $sync.WPFToggleWindowsUpdate.Tag = $false
        Invoke-WPFWindowsUpdate

        Should -Invoke Invoke-WPFUpdatesdefault -Times 1 -Exactly
        Should -Not -Invoke Invoke-WPFUpdatesdisable
        Should -Invoke Set-WinUtilTweaksProgressIndicator -Times 1 -Exactly -ParameterFilter { $Label -eq "Windows Update setting applied" -and $Percent -eq 100 }
        Should -Not -Invoke Set-WinUtilTweaksProgressIndicator -ParameterFilter { $Label -match 'restart' }
        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeTrue
        $sync.ProcessRunning | Should -BeFalse
    }

    It "keeps both tab switches synchronized from either control" {
        $sync.WPFToggleMaintenanceWindowsUpdate = [pscustomobject]@{
            IsChecked = $true; Tag = $true; IsEnabled = $true; ToolTip = 'Windows Update'
        }
        $sync.WPFToggleMaintenanceWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate -Name WPFToggleMaintenanceWindowsUpdate
        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeFalse
        $sync.WPFToggleWindowsUpdate.Tag | Should -BeFalse
        $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeTrue
        $sync.WPFToggleMaintenanceWindowsUpdate.Tag | Should -BeFalse
        $sync.WPFToggleWindowsUpdate.IsChecked = $true
        Invoke-WPFWindowsUpdate
        $sync.WPFToggleMaintenanceWindowsUpdate.IsChecked | Should -BeTrue
        $sync.WPFToggleMaintenanceWindowsUpdate.Tag | Should -BeTrue
        $sync.WPFToggleMaintenanceWindowsUpdate.IsEnabled | Should -BeTrue
        Should -Invoke Invoke-WPFUpdatesdisable -Times 1 -Exactly
        Should -Invoke Invoke-WPFUpdatesdefault -Times 1 -Exactly
    }

    It "disables a newly initialized twin while an operation is pending without duplicating work" {
        $dispatcher = [pscustomobject]@{ Callback = $null; Arguments = $null }
        $dispatcher | Add-Member ScriptMethod BeginInvoke {
            param($callback,$arguments)
            $this.Callback = $callback; $this.Arguments = $arguments
        }
        $sync.Form = [pscustomobject]@{ Dispatcher = $dispatcher }
        $sync.WPFToggleWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate
        $sync.WPFToggleMaintenanceWindowsUpdate = [pscustomobject]@{
            IsChecked = $true; Tag = $true; IsEnabled = $true; ToolTip = 'Windows Update'
        }
        Invoke-WPFWindowsUpdate -Name WPFToggleMaintenanceWindowsUpdate -Refresh
        $sync.WPFToggleMaintenanceWindowsUpdate.IsEnabled | Should -BeFalse
        Should -Invoke Invoke-WPFRunspace -Times 1 -Exactly
        $dispatcher.Callback.Invoke($dispatcher.Arguments[0])
        $sync.WPFToggleMaintenanceWindowsUpdate.IsChecked | Should -BeFalse
        $sync.WPFToggleMaintenanceWindowsUpdate.IsEnabled | Should -BeTrue
        $sync.WindowsUpdateRunning | Should -BeFalse
    }

    It "disables updates when switched off" {
        $sync.WPFToggleWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate

        Should -Invoke Invoke-WPFUpdatesdisable -Times 1 -Exactly
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        Should -Invoke Set-WinUtilTweaksProgressIndicator -Times 1 -Exactly -ParameterFilter { $Label -eq "Windows Update setting applied" -and $Percent -eq 100 }
        Should -Not -Invoke Set-WinUtilTweaksProgressIndicator -ParameterFilter { $Label -match 'restart' }
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

    It "queues completion and performs status queries before dispatch for off/on cycles" {
        $dispatcher = [pscustomobject]@{ Callback = $null; Arguments = $null }
        $dispatcher | Add-Member ScriptMethod BeginInvoke {
            param($callback, $arguments)
            $this.Callback = $callback
            $this.Arguments = $arguments
        }
        $sync.Form = [pscustomobject]@{ Dispatcher = $dispatcher }
        Mock Invoke-WPFUIThread { throw 'No synchronous worker dispatch is allowed' }
        foreach ($enabled in @($false,$true,$false,$true)) {
            $sync.WPFToggleWindowsUpdate.IsChecked = $enabled
            Invoke-WPFWindowsUpdate
            $sync.ProcessRunning | Should -BeTrue
            $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeFalse
            $dispatcher.Arguments[0].State | Should -Be $enabled
            $dispatcher.Callback.Invoke($dispatcher.Arguments[0])
            $sync.ProcessRunning | Should -BeFalse
            $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeTrue
            $sync.WPFToggleWindowsUpdate.Tag | Should -Be $enabled
        }
        Should -Invoke Get-WinUtilWindowsUpdateStatus -Times 4 -Exactly
        Should -Invoke Invoke-WPFUpdatesdefault -Times 2 -Exactly
        Should -Invoke Invoke-WPFUpdatesdisable -Times 2 -Exactly
        Should -Not -Invoke Invoke-WPFUIThread
    }

    It "defers initial status reads and does not duplicate refresh while work is queued" {
        Mock Invoke-WPFRunspace {}
        Invoke-WPFWindowsUpdate -Refresh
        Invoke-WPFWindowsUpdate -Refresh
        $sync.ProcessRunning | Should -BeTrue
        $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeFalse
        Should -Invoke Invoke-WPFRunspace -Times 1 -Exactly
        Should -Not -Invoke Get-WinUtilWindowsUpdateStatus
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        Should -Not -Invoke Invoke-WPFUpdatesdisable
        Should -Not -Invoke Show-WinUtilMessage
    }

    It "shows worker failures only from the queued UI completion after clearing busy" {
        $dispatcher = [pscustomobject]@{ Callback = $null; Arguments = $null }
        $dispatcher | Add-Member ScriptMethod BeginInvoke {
            param($callback, $arguments)
            $this.Callback = $callback
            $this.Arguments = $arguments
        }
        $sync.Form = [pscustomobject]@{ Dispatcher = $dispatcher }
        Mock Invoke-WPFUpdatesdisable { throw 'fixture failure' }
        Mock Invoke-WPFUIThread { throw 'No synchronous worker dispatch is allowed' }
        Mock Show-WinUtilMessage {
            if ($Icon -eq 'Error') {
                $sync.ProcessRunning | Should -BeFalse
                $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeTrue
            }
            'Yes'
        }
        $sync.WPFToggleWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate
        $sync.ProcessRunning | Should -BeTrue
        Should -Not -Invoke Show-WinUtilMessage -ParameterFilter { $Icon -eq 'Error' }
        $dispatcher.Callback.Invoke($dispatcher.Arguments[0])
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Icon -eq 'Error' -and $Message -like '*fixture failure*' }
        Should -Invoke Get-WinUtilWindowsUpdateStatus -Times 1 -Exactly
    }

    It "refreshes status during another workflow without releasing that workflow's busy flag" {
        $sync.ProcessRunning = $true
        $script:updateEnabled = $false
        Invoke-WPFWindowsUpdate -Refresh
        $sync.ProcessRunning | Should -BeTrue
        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeFalse
        Should -Invoke Get-WinUtilWindowsUpdateStatus -Times 1 -Exactly
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        Should -Not -Invoke Invoke-WPFUpdatesdisable
    }

    It "restores the previous switch state if runspace submission fails" {
        Mock Invoke-WPFRunspace { throw 'queue unavailable' }
        $sync.WPFToggleWindowsUpdate.IsChecked = $false
        Invoke-WPFWindowsUpdate
        $sync.ProcessRunning | Should -BeFalse
        $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeTrue
        $sync.WPFToggleWindowsUpdate.IsChecked | Should -BeTrue
        Should -Not -Invoke Get-WinUtilWindowsUpdateStatus
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Message -like '*queue unavailable*' }
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

        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq "Windows Update settings applied." }
        Should -Not -Invoke Write-Host -ParameterFilter { $Object -match 'restart' }
        Should -Not -Invoke Write-WinUtilLog -ParameterFilter { $Message -match 'restart required' }

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

        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq "Windows Update settings applied." }
        Should -Not -Invoke Write-Host -ParameterFilter { $Object -match 'restart' }
        Should -Not -Invoke Write-WinUtilLog -ParameterFilter { $Message -match 'restart required' }

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

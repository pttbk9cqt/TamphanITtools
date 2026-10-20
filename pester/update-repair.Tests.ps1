BeforeAll {
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    . "$root/functions/private/Repair-WinUtilWindowsUpdate.ps1"
    . "$root/functions/public/Invoke-WPFRepairWindowsUpdate.ps1"
    . "$root/functions/public/Invoke-WPFButton.ps1"
    function Get-WinUtilWindowsUpdateStatus { $true }
    function Invoke-WPFUpdatesdefault {}
    function Write-WinUtilLog { param($Component,$Level,$Message) }
    function Show-WinUtilMessage { param($Title,$Message,$Button,$Icon) }
    function Set-WinUtilTweaksProgressIndicator { param($Visible,$Label,$Percent) }
    function Invoke-WPFRunspace { param($ArgumentList,$ScriptBlock) }
}

Describe 'Windows Update cache repair' {
    BeforeEach {
        $script:oldRoot = $env:SystemRoot
        $env:SystemRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$env:SystemRoot/SoftwareDistribution","$env:SystemRoot/System32/catroot2" -Force | Out-Null
        $script:serviceEvents = [System.Collections.Generic.List[string]]::new()
        $script:stopFailure = ''
        $script:startFailure = ''
        Mock Write-WinUtilLog {}
        Mock Get-WinUtilWindowsUpdateStatus { $true }
        Mock Invoke-WPFUpdatesdefault {}
        Mock Get-Service {
            $service = [pscustomobject]@{ Name = $Name; Status = 'Running' }
            $service | Add-Member ScriptMethod Refresh {}
            $service | Add-Member ScriptMethod Stop {
                $script:serviceEvents.Add("Stop:$($this.Name)")
                $this.Status = 'Stopped'
            }
            $service | Add-Member ScriptMethod Start {
                $script:serviceEvents.Add("Start:$($this.Name)")
                if ($this.Name -eq $script:startFailure) { throw 'start failed' }
                $this.Status = 'Running'
            }
            $service | Add-Member ScriptMethod WaitForStatus {
                param($status,$timeout)
                if ($timeout.TotalSeconds -ne 20) { throw 'Expected bounded wait' }
                if ($status -eq 'Stopped' -and $this.Name -eq $script:stopFailure) { throw 'stop timeout' }
            }
            $service
        }
    }
    AfterEach { $env:SystemRoot = $script:oldRoot }

    It 'renames both caches to unique backups and starts all services' {
        $message = Repair-WinUtilWindowsUpdate
        Test-Path "$env:SystemRoot/SoftwareDistribution" | Should -BeFalse
        @(Get-ChildItem "$env:SystemRoot" -Filter 'SoftwareDistribution.winutil-backup-*').Count | Should -Be 1
        @(Get-ChildItem "$env:SystemRoot/System32" -Filter 'catroot2.winutil-backup-*').Count | Should -Be 1
        @($script:serviceEvents | Where-Object { $_ -like 'Start:*' }).Count | Should -Be 3
        $message | Should -Match 'does not guarantee'
        Should -Not -Invoke Invoke-WPFUpdatesdefault
    }

    It 'restores defaults only when update state is disabled' {
        Mock Get-WinUtilWindowsUpdateStatus { $false }
        Repair-WinUtilWindowsUpdate | Out-Null
        Should -Invoke Invoke-WPFUpdatesdefault -Times 1 -Exactly
    }

    It 'does not rename caches when a service stop times out' {
        $script:stopFailure = 'wuauserv'
        { Repair-WinUtilWindowsUpdate } | Should -Throw '*stop timeout*'
        Test-Path "$env:SystemRoot/SoftwareDistribution" | Should -BeTrue
        Test-Path "$env:SystemRoot/System32/catroot2" | Should -BeTrue
        $script:serviceEvents | Should -Contain 'Start:bits'
        $script:serviceEvents | Should -Contain 'Start:wuauserv'
    }

    It 'rolls back the first rename if the second cache is locked' {
        Mock Rename-Item { throw 'cache locked' } -ParameterFilter { $LiteralPath -like '*catroot2' }
        { Repair-WinUtilWindowsUpdate } | Should -Throw '*cache locked*'
        Test-Path "$env:SystemRoot/SoftwareDistribution" | Should -BeTrue
        Test-Path "$env:SystemRoot/System32/catroot2" | Should -BeTrue
    }

    It 'reports service restart failures and retains backups' {
        $script:startFailure = 'bits'
        { Repair-WinUtilWindowsUpdate } | Should -Throw '*start failed*'
        @(Get-ChildItem "$env:SystemRoot" -Filter 'SoftwareDistribution.winutil-backup-*').Count | Should -Be 1
        $script:serviceEvents | Should -Contain 'Start:cryptsvc'
    }

    It 'rejects redirected cache directories before touching services' {
        Mock Get-Item { [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::ReparsePoint } } -ParameterFilter { $LiteralPath -like '*SoftwareDistribution' }
        { Repair-WinUtilWindowsUpdate } | Should -Throw '*Unsafe cache directory*'
        Should -Not -Invoke Get-Service
        Should -Not -Invoke Invoke-WPFUpdatesdefault
        Test-Path "$env:SystemRoot/SoftwareDistribution" | Should -BeTrue
    }
}

Describe 'Repair button and UI completion' {
    BeforeEach {
        $script:sync = @{ ProcessRunning = $false; WindowsUpdateRunning = $false; configs = @{ maintenance = @{} }
            WPFToggleWindowsUpdate = [pscustomobject]@{ IsChecked = $false; Tag = $false; IsEnabled = $true; ToolTip = '' }
            WPFToggleMaintenanceWindowsUpdate = [pscustomobject]@{ IsChecked = $false; Tag = $false; IsEnabled = $true; ToolTip = '' }
            WPFRepairWindowsUpdate = [pscustomobject]@{ IsEnabled = $true }
        }
        Mock Show-WinUtilMessage { 'Yes' }
        Mock Write-WinUtilLog {}
        Mock Set-WinUtilTweaksProgressIndicator {}
        Mock Repair-WinUtilWindowsUpdate { 'Cache reset completed.' }
        Mock Get-WinUtilWindowsUpdateStatus { $true }
        Mock Invoke-WPFRunspace { & $ScriptBlock $ArgumentList }
    }

    It 'does nothing if confirmation is declined' {
        Mock Show-WinUtilMessage { 'No' }
        Invoke-WPFRepairWindowsUpdate
        Should -Not -Invoke Invoke-WPFRunspace
        Should -Not -Invoke Repair-WinUtilWindowsUpdate
        $sync.ProcessRunning | Should -BeFalse
    }

    It 'blocks concurrent operations' {
        $sync.ProcessRunning = $true
        Invoke-WPFRepairWindowsUpdate
        Should -Not -Invoke Invoke-WPFRunspace
    }

    It 'routes the button and synchronizes both switches on completion' {
        Invoke-WPFButton WPFRepairWindowsUpdate
        Should -Invoke Repair-WinUtilWindowsUpdate -Times 1 -Exactly
        $sync.WPFToggleWindowsUpdate.Tag | Should -BeTrue
        $sync.WPFToggleMaintenanceWindowsUpdate.Tag | Should -BeTrue
        $sync.WPFRepairWindowsUpdate.IsEnabled | Should -BeTrue
        $sync.ProcessRunning | Should -BeFalse
        $sync.WindowsUpdateRunning | Should -BeFalse
    }

    It 'reports worker failure and releases busy state' {
        Mock Repair-WinUtilWindowsUpdate { throw 'simulated error' }
        Invoke-WPFRepairWindowsUpdate
        Should -Invoke Show-WinUtilMessage -Times 1 -ParameterFilter { $Icon -eq 'Error' -and $Message -match 'simulated error' }
        $sync.ProcessRunning | Should -BeFalse
    }

    It 'recovers when runspace submission fails' {
        Mock Invoke-WPFRunspace { throw 'queue failed' }
        Invoke-WPFRepairWindowsUpdate
        $sync.WPFRepairWindowsUpdate.IsEnabled | Should -BeTrue
        $sync.ProcessRunning | Should -BeFalse
        Should -Not -Invoke Repair-WinUtilWindowsUpdate
    }

    It 'reports unreadable final state without claiming switch state' {
        Mock Get-WinUtilWindowsUpdateStatus { throw 'state unavailable' }
        Invoke-WPFRepairWindowsUpdate
        $sync.WPFToggleWindowsUpdate.IsEnabled | Should -BeFalse
        $sync.WPFToggleMaintenanceWindowsUpdate.IsEnabled | Should -BeFalse
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Show-WinUtilMessage -Times 1 -ParameterFilter { $Message -match 'Unable to refresh update state' }
    }

    It 'queues completion instead of synchronously dispatching worker dialogs' {
        $dispatcher = [pscustomobject]@{ Callback = $null; Arguments = $null }
        $dispatcher | Add-Member ScriptMethod BeginInvoke { param($callback,$arguments) $this.Callback = $callback; $this.Arguments = $arguments }
        $sync.Form = [pscustomobject]@{ Dispatcher = $dispatcher }
        Invoke-WPFRepairWindowsUpdate
        $sync.ProcessRunning | Should -BeTrue
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly
        $dispatcher.Callback.Invoke($dispatcher.Arguments[0])
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Show-WinUtilMessage -Times 2 -Exactly
    }
}

Describe 'Repair real dispatcher responsiveness' {
    It 'places repair in its own panel inside Update' {
        [xml]$xaml = Get-Content "$root/xaml/inputXML.xaml" -Raw
        $button = $xaml.SelectSingleNode('//*[@Name="WPFRepairWindowsUpdate"]')
        $button | Should -Not -BeNullOrEmpty
        $button.SelectSingleNode('ancestor::*[local-name()="TabItem"]/@Header').Value | Should -Be Update
        $button.ParentNode.ParentNode.SelectSingleNode('.//*[local-name()="TextBlock"]/@Text').Value | Should -Be 'Fix no respoding Update'
    }
    It 'keeps WPF responsive with safe success and failure fixtures' {
        $powershellPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = & $powershellPath -NoProfile -STA -ExecutionPolicy Bypass -File "$PSScriptRoot/fixtures/UpdateRepairResponsive.ps1" 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output | Out-String)
        ($output | Out-String) | Should -Match 'PASS: cache repair kept real WPF responsive'
    }
}

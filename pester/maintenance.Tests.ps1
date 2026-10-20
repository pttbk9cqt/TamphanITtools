BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFMaintenance.ps1')
    . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFMaintenanceToggle.ps1')
    . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFButton.ps1')
    . (Join-Path $script:repoRoot 'functions/private/Invoke-WinUtilMaintenance.ps1')
    function Show-WinUtilMessage { param($Message,$Title,$Button,$Icon) }
    function Write-WinUtilLog { param($Message,$Level,$Component) }
    function Set-WinUtilTweaksProgressIndicator { param($Visible,$Label,$Percent) }
    function Invoke-WPFUIThread { param($ScriptBlock) & $ScriptBlock }
    function Invoke-WPFRunspace { param($ArgumentList,$ScriptBlock) }
    function Get-ScheduledTask { param($TaskName) }
    function Get-WinUtilOriginalMaintenanceStatus { param($Status) $true }
    function Invoke-WPFWindowsUpdate { param([switch]$Refresh,[string]$Name) }
    function Invoke-WPFFixesWinget { }
    function Restore-WPFMaintenanceWindow { }


}

Describe 'Maintenance actions' {
    BeforeEach {
        $script:sync = [hashtable]::Synchronized(@{
            configs = @{ maintenance = Get-Content (Join-Path $script:repoRoot 'config/maintenance.json') -Raw | ConvertFrom-Json }
            ProcessRunning = $false
        })
        Mock Show-WinUtilMessage { 'Yes' }
        Mock Write-WinUtilLog {}
        Mock Set-WinUtilTweaksProgressIndicator {}
        Mock Invoke-WPFRunspace {}
        Mock Restore-WPFMaintenanceWindow {}
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
    }

    It 'routes every config button to a supported action' {
        Mock Invoke-WPFMaintenance {}
        foreach ($entry in $sync.configs.maintenance.PSObject.Properties | Where-Object { $_.Value.Type -eq 'Button' -and $_.Value.Action }) {
            { Invoke-WPFButton -Button $entry.Name } | Should -Not -Throw
        }
        Should -Invoke Invoke-WPFMaintenance -Times 3 -Exactly
        Should -Invoke Invoke-WPFMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'ExportInventory' }
        Should -Invoke Invoke-WPFMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'Tasks' }
    }

    It 'routes WinGet reinstall and all fourteen legacy panels from Maintenance' {
        Mock Invoke-WPFFixesWinget {}
        $script:openedPanels = [Collections.Generic.List[string]]::new()
        Mock Invoke-Command { $script:openedPanels.Add($ScriptBlock.ToString()) }
        Mock Invoke-WPFMaintenance {}
        Invoke-WPFButton -Button WPFFixesWinget
        $panels = @($sync.configs.maintenance.PSObject.Properties | Where-Object { $_.Value.Category -eq 'Legacy Windows Panels' })
        $panels.Count | Should -Be 14
        foreach ($panel in $panels) {
            Invoke-WPFButton -Button $panel.Name
        }
        @($script:openedPanels) | Should -Be @($panels | ForEach-Object { $_.Value.InvokeScript[0] })
        Should -Invoke Invoke-WPFFixesWinget -Times 1 -Exactly
        Should -Not -Invoke Invoke-WPFMaintenance
    }

    It 'maps task switches to create and remove actions' {
        $script:sync.WPFToggleMaintenanceTasks = [pscustomobject]@{ IsChecked = $true; Tag = $false; IsEnabled = $true; ToolTip = $null }
        Mock Invoke-WPFMaintenance {}
        Invoke-WPFMaintenanceToggle -Name WPFToggleMaintenanceTasks
        $script:sync.WPFToggleMaintenanceTasks.IsChecked = $false
        Invoke-WPFMaintenanceToggle -Name WPFToggleMaintenanceTasks
        Should -Invoke Invoke-WPFMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'InstallTasks' -and $StateToggle -eq 'WPFToggleMaintenanceTasks' }
        Should -Invoke Invoke-WPFMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'RemoveTasks' -and $StateToggle -eq 'WPFToggleMaintenanceTasks' }
    }

    It 'maps monitoring switch to create and remove actions' {
        $script:sync.WPFToggleMaintenanceMonitor = [pscustomobject]@{ IsChecked = $true; Tag = $false; IsEnabled = $true; ToolTip = $null }
        Mock Invoke-WPFMaintenance {}
        Invoke-WPFMaintenanceToggle -Name WPFToggleMaintenanceMonitor
        $script:sync.WPFToggleMaintenanceMonitor.IsChecked = $false
        Invoke-WPFMaintenanceToggle -Name WPFToggleMaintenanceMonitor
        Should -Invoke Invoke-WPFMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'InstallMonitor' }
        Should -Invoke Invoke-WPFMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'RemoveMonitor' }
    }

    It 'restores a task switch when the user declines the change' {
        $script:sync.WPFToggleMaintenanceTasks = [pscustomobject]@{ IsChecked = $false; Tag = $true; IsEnabled = $true; ToolTip = $null }
        Mock Show-WinUtilMessage { 'No' }
        Mock Invoke-WPFMaintenanceToggle {
            $script:sync.WPFToggleMaintenanceTasks.IsChecked = $script:sync.WPFToggleMaintenanceTasks.Tag
        } -ParameterFilter { $Refresh }
        Invoke-WPFMaintenance -Action RemoveTasks -StateToggle WPFToggleMaintenanceTasks
        $script:sync.WPFToggleMaintenanceTasks.IsChecked | Should -BeTrue
        Should -Invoke Invoke-WPFRunspace -Times 0
    }

    It 'does not start maintenance when another operation is active' {
        $sync.ProcessRunning = $true
        Invoke-WPFMaintenance -Action ExportInventory
        Should -Invoke Invoke-WPFRunspace -Times 0
        Should -Invoke Start-Process -Times 0
    }

    It 'opens Task Scheduler even while background maintenance is active' {
        $sync.ProcessRunning = $true
        Invoke-WPFMaintenance -Action Tasks
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'taskschd.msc' }
        Should -Not -Invoke Invoke-WPFRunspace
    }

    It 'does not start a declined action' {
        Mock Show-WinUtilMessage { 'No' }
        Invoke-WPFMaintenance -Action ExportInventory
        Should -Invoke Invoke-WPFRunspace -Times 0
        $sync.ProcessRunning | Should -BeFalse
    }

    It 'reserves the process flag before submitting work' {
        Mock Invoke-WPFRunspace {
            $sync.ProcessRunning | Should -BeTrue
            $ArgumentList.Action | Should -Be ExportInventory
        }
        Invoke-WPFMaintenance -Action ExportInventory
        Should -Invoke Invoke-WPFRunspace -Times 1
    }

    It 'clears the busy flag and reports a worker failure' {
        Mock Invoke-WinUtilMaintenance { throw 'worker failed' }
        Mock Invoke-WPFRunspace { & $ScriptBlock $ArgumentList }
        Invoke-WPFMaintenance -Action ExportInventory
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Write-WinUtilLog -Times 1 -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*worker failed*' }
    }

    It 'clears the busy flag after success' {
        Mock Invoke-WinUtilMaintenance { 'Finished' }
        Mock Invoke-WPFRunspace { & $ScriptBlock $ArgumentList }
        Invoke-WPFMaintenance -Action ExportInventory
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Set-WinUtilTweaksProgressIndicator -Times 1 -ParameterFilter { $Percent -eq 100 }
        Should -Invoke Restore-WPFMaintenanceWindow -Times 1 -Exactly
    }

    It 'queues completion without blocking the worker and refreshes task state before the dialog' {
        $sync.WPFToggleMaintenanceTasks = [pscustomobject]@{ IsChecked = $false; Tag = $false; IsEnabled = $true; ToolTip = $null }
        $dispatcher = [pscustomobject]@{ Callback = $null; Arguments = $null }
        $dispatcher | Add-Member ScriptMethod BeginInvoke {
            param($callback, $arguments)
            $this.Callback = $callback
            $this.Arguments = $arguments
        }
        $sync.Form = [pscustomobject]@{ Dispatcher = $dispatcher }
        Mock Invoke-WinUtilMaintenance { 'Tasks verified' }
        Mock Invoke-WPFRunspace { & $ScriptBlock $ArgumentList }
        Mock Get-WinUtilOriginalMaintenanceStatus { $true }
        Mock Invoke-WPFUIThread { throw 'Worker must not synchronously dispatch to WPF' }
        Mock Show-WinUtilMessage {
            if ($Message -eq 'Tasks verified') {
                $sync.ProcessRunning | Should -BeFalse
                $sync.WPFToggleMaintenanceTasks.IsChecked | Should -BeTrue
                $sync.WPFToggleMaintenanceTasks.Tag | Should -BeTrue
            }
            'Yes'
        }

        Invoke-WPFMaintenance -Action InstallTasks -StateToggle WPFToggleMaintenanceTasks

        $sync.ProcessRunning | Should -BeTrue
        Should -Invoke Get-WinUtilOriginalMaintenanceStatus -Times 1 -Exactly
        Should -Invoke Show-WinUtilMessage -Times 0 -ParameterFilter { $Message -eq 'Tasks verified' }
        $dispatcher.Callback.Invoke($dispatcher.Arguments[0])
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Message -eq 'Tasks verified' }
    }

}

Describe 'Maintenance payload' {
    It 'embeds every standalone script byte-for-byte in the compiled artifact' {
        Push-Location $script:repoRoot
        try { & ./Compile.ps1 } finally { Pop-Location }
        $compiled = Get-Content (Join-Path $script:repoRoot 'winutil.ps1') -Raw
        $match = [regex]::Match($compiled, "(?s)\`$sync\.configs\.maintenanceScripts = @'\r?\n(?<json>.*?)\r?\n'@ \| ConvertFrom-Json")
        $match.Success | Should -BeTrue
        $payloads = $match.Groups['json'].Value | ConvertFrom-Json
        foreach ($file in Get-ChildItem (Join-Path $script:repoRoot 'maintenance') -Filter *.ps1) {
            $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloads.($file.BaseName)))
            $decoded | Should -BeExactly (Get-Content $file.FullName -Raw -Encoding UTF8)
            $parseErrors = $null
            [void][Management.Automation.Language.Parser]::ParseInput($decoded,[ref]$null,[ref]$parseErrors)
            $parseErrors.Count | Should -Be 0
        }
    }
}

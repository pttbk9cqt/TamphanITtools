BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFMaintenance.ps1')
    . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFMaintenanceToggle.ps1')
    . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFButton.ps1')
    . (Join-Path $script:repoRoot 'functions/private/Invoke-WinUtilMaintenance.ps1')
    . (Join-Path $script:repoRoot 'functions/private/Invoke-WinUtilMaintenanceAccounts.ps1')
    . (Join-Path $script:repoRoot 'functions/private/Invoke-WinUtilMaintenanceInstall.ps1')
    function Show-WinUtilMessage { param($Message,$Title,$Button,$Icon) }
    function Show-WinUtilMaintenanceDialog { param($Action) }
    function Write-WinUtilLog { param($Message,$Level,$Component) }
    function Set-WinUtilTweaksProgressIndicator { param($Visible,$Label,$Percent) }
    function Invoke-WPFUIThread { param($ScriptBlock) & $ScriptBlock }
    function Invoke-WPFRunspace { param($ArgumentList,$ScriptBlock) }
    function Start-ScheduledTask { param($TaskName) }
    function Get-ScheduledTask { param($TaskName) }
    function Enable-ScheduledTask { param($TaskName) }
    function Get-WinUtilOriginalMaintenanceStatus { param($Status) $true }
    function Invoke-WPFWindowsUpdate { param([switch]$Refresh) }

    function Import-MaintenanceFunction {
        param([string]$File,[string]$Name)
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:repoRoot $File),[ref]$null,[ref]$null)
        $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }, $true)
        . ([scriptblock]::Create($definition.Extent.Text.Replace("function $Name", "function script:$Name")))
    }
    Import-MaintenanceFunction 'maintenance/Common.ps1' 'Get-DiskBand'
    Import-MaintenanceFunction 'maintenance/Common.ps1' 'Get-ManagedVolume'
    Import-MaintenanceFunction 'maintenance/Common.ps1' 'Get-ManagedPartition'
    Import-MaintenanceFunction 'maintenance/Cleaner.ps1' 'Remove-OldTempFiles'
    Import-MaintenanceFunction 'maintenance/Inventory.ps1' 'Get-LicenseText'
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
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Start-ScheduledTask {}
        Mock Enable-ScheduledTask {}
        Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
    }

    It 'routes every config button to a supported action' {
        Mock Invoke-WPFMaintenance {}
        foreach ($entry in $sync.configs.maintenance.PSObject.Properties | Where-Object { $_.Value.Type -eq 'Button' }) {
            { Invoke-WPFButton -Button $entry.Name } | Should -Not -Throw
        }
        Should -Invoke Invoke-WPFMaintenance -Times 2 -Exactly
        Should -Invoke Invoke-WPFMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'ExportInventory' }
        Should -Invoke Invoke-WPFMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'Tasks' }
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
        Invoke-WPFMaintenance -Action Clean
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
        Invoke-WPFMaintenance -Action Clean
        Should -Invoke Invoke-WPFRunspace -Times 0
        $sync.ProcessRunning | Should -BeFalse
    }

    It 'reserves the process flag before submitting work' {
        Mock Invoke-WPFRunspace {
            $sync.ProcessRunning | Should -BeTrue
            $ArgumentList.Action | Should -Be Clean
            $ArgumentList.Options | Should -BeOfType hashtable
        }
        Invoke-WPFMaintenance -Action Clean
        Should -Invoke Invoke-WPFRunspace -Times 1
    }

    It 'clears the busy flag and reports a worker failure' {
        Mock Invoke-WinUtilMaintenance { throw 'worker failed' }
        Mock Invoke-WPFRunspace { & $ScriptBlock $ArgumentList }
        Invoke-WPFMaintenance -Action Clean
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Write-WinUtilLog -Times 1 -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*worker failed*' }
    }

    It 'clears the busy flag after success' {
        Mock Invoke-WinUtilMaintenance { 'Finished' }
        Mock Invoke-WPFRunspace { & $ScriptBlock $ArgumentList }
        Invoke-WPFMaintenance -Action Clean
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Set-WinUtilTweaksProgressIndicator -Times 1 -ParameterFilter { $Percent -eq 100 }
    }

    It 'does not silently resume a paused monitoring task' {
        Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Disabled' } }
        { Invoke-WinUtilMaintenance -Action Monitor } | Should -Throw '*paused*'
        Should -Invoke Start-ScheduledTask -Times 0
        Should -Invoke Enable-ScheduledTask -Times 0
    }

    It 'reports task submission without claiming the disk check completed' {
        Invoke-WinUtilMaintenance -Action Monitor | Should -Match 'requested'
        Should -Invoke Start-ScheduledTask -Times 1 -ParameterFilter { $TaskName -eq 'IT-MAINTENANCE' }
    }

    It 'propagates a standalone worker exit failure' {
        Mock Test-Path { $true }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
        { Invoke-WinUtilMaintenance -Action Clean } | Should -Throw '*exit code 1*'
    }

    It 'does not launch a worker before installation' {
        Mock Test-Path { $false }
        { Invoke-WinUtilMaintenance -Action RestoreD } | Should -Throw '*Install maintenance first*'
        Should -Invoke Start-Process -Times 0
    }
}

Describe 'Maintenance setup preflight' {
    BeforeEach {
        $script:employee = [pscustomobject]@{ Name = 'employee'; FullName = 'Test Employee'; Enabled = $true; SID = [Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1001' }
        $script:admin = [pscustomobject]@{ Name = 'Administrator'; FullName = 'Administrator'; SID = [Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-500' }
        $script:adminRenamed = $false
        Mock Get-CimInstance {
            if ($script:adminRenamed) { throw 'CIM query after administrator rename' }
            if ($ClassName -eq 'Win32_UserProfile') { return @() }
            [pscustomobject]@{ DomainRole = 1; PartOfDomain = $false }
        }
        Mock Get-LocalUser {
            if ($SID) { return $script:admin }
            if ($Name -eq 'adminbcmbp') { return $null }
            if ($Name -eq 'employee') { return $script:employee }
            return $script:admin
        }
        Mock Get-LocalGroup { [pscustomobject]@{ Name = 'Users'; SID = [Security.Principal.SecurityIdentifier]'S-1-5-32-545' } }
        Mock Get-LocalGroupMember { @($script:admin, $script:employee) }
        Mock New-LocalUser { throw 'Unexpected account creation' }
        Mock Set-LocalUser {}
        Mock Enable-LocalUser {}
        Mock Add-LocalGroupMember {}
        Mock Remove-LocalGroupMember {}
        Mock Rename-Computer {}
        Mock Rename-LocalUser { $script:adminRenamed = $true }
        Mock New-Item { throw 'Unexpected filesystem mutation' }
        Mock Register-ScheduledTask { throw 'Unexpected task registration' }
        $script:accountOptions = @{
            NewComputerName = 'BCMBP-TEST'
            EmployeeFullName = 'Test Employee'
            EmployeeUserName = 'employee'
            AdminFullName = 'IT Administrator'
        }
    }

    It 'preserves existing passwords and renames the administrator last' {
        Invoke-WinUtilMaintenanceAccounts @accountOptions
        Should -Invoke Set-LocalUser -Times 0 -ParameterFilter { $null -ne $Password }
        Should -Invoke Rename-LocalUser -Times 1
        Should -Invoke New-LocalUser -Times 0
        Should -Invoke Register-ScheduledTask -Times 0
    }

    It 'requires a new employee password before any machine or account changes' {
        $script:employee = $null
        { Invoke-WinUtilMaintenanceAccounts @accountOptions } | Should -Throw '*non-empty password*'
        Should -Invoke Rename-Computer -Times 0
        Should -Invoke Set-LocalUser -Times 0
        Should -Invoke New-LocalUser -Times 0
    }

    It 'rejects a full-name collision without changing accounts' {
        $accountOptions.EmployeeFullName = 'Another Employee'
        { Invoke-WinUtilMaintenanceAccounts @accountOptions } | Should -Throw '*different full name*'
        Should -Invoke Set-LocalUser -Times 0
        Should -Invoke Rename-Computer -Times 0
    }

    It 'requires the employee desktop profile before installation mutates files or tasks' {
        { Invoke-WinUtilMaintenanceInstall -EmployeeUserName employee } | Should -Throw '*Sign in as the employee first*'
        Should -Invoke New-Item -Times 0
        Should -Invoke Register-ScheduledTask -Times 0
        Should -Invoke Set-LocalUser -Times 0
    }
}

Describe 'Ported maintenance safety' {
    It 'preserves free-space boundaries' {
        Get-DiskBand (20GB - 1) | Should -Be Critical
        Get-DiskBand 20GB | Should -Be Warning
        Get-DiskBand 30GB | Should -Be Warning
        Get-DiskBand (30GB + 1) | Should -Be Normal
    }

    It 'treats missing license data as Unknown' {
        Get-LicenseText $null | Should -Be Unknown
        Get-LicenseText 1 | Should -Be Licensed
    }

    It 'resolves a live GUID and rejects unsafe data volumes' {
        $script:volume = [pscustomobject]@{ DeviceID = 'test-guid'; FreeSpace = 50GB; Capacity = 100GB; DriveLetter = 'D:'; BootVolume = $false; SystemVolume = $false; PageFilePresent = $false; DriveType = 3 }
        $script:partition = [pscustomobject]@{ AccessPaths = @('test-guid'); DiskNumber = 9; PartitionNumber = 7; IsBoot = $false; IsSystem = $false; DriveLetter = 'D' }
        $script:disk = [pscustomobject]@{ IsOffline = $false; IsReadOnly = $false; BusType = 'SATA' }
        Mock Get-CimInstance { $script:volume }
        Mock Get-Partition { $script:partition }
        Mock Get-Disk { $script:disk }
        $config = [pscustomobject]@{ VolumeGUID = 'test-guid'; DiskNumber = 1 }
        (Get-ManagedPartition $config).DiskNumber | Should -Be 9
        $script:partition.IsSystem = $true
        { Get-ManagedPartition $config } | Should -Throw '*Refusing*'
        $script:partition.IsSystem = $false
        $script:volume.PageFilePresent = $true
        { Get-ManagedPartition $config } | Should -Throw '*Refusing*'
        $script:volume.PageFilePresent = $false
        $script:disk.BusType = 'USB'
        { Get-ManagedPartition $config } | Should -Throw '*Refusing*'
        $script:disk.BusType = 'SATA'
        $config.VolumeGUID = 'other-guid'
        { Get-ManagedPartition $config } | Should -Throw
    }

    It 'cleans only old temp files in the selected directory' {
        $allowed = Join-Path $TestDrive 'Temp'
        New-Item -ItemType Directory -Path $allowed | Out-Null
        $old = Join-Path $allowed 'old.tmp'
        $fresh = Join-Path $allowed 'fresh.tmp'
        $outside = Join-Path $TestDrive 'keep.txt'
        foreach ($path in @($old,$fresh,$outside)) { Set-Content -LiteralPath $path -Value 'fixture' }
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-10)
        (Get-Item $outside).LastWriteTime = (Get-Date).AddDays(-10)
        $cutoff = (Get-Date).AddDays(-7)
        $script:count = 0
        $script:skipped = 0
        Remove-OldTempFiles $allowed
        Test-Path $old | Should -BeFalse
        Test-Path $fresh | Should -BeTrue
        Test-Path $outside | Should -BeTrue
    }

    It 'keeps setup responsibilities separate and never embeds sample passwords' {
        $account = Get-Content (Join-Path $script:repoRoot 'functions/private/Invoke-WinUtilMaintenanceAccounts.ps1') -Raw
        $install = Get-Content (Join-Path $script:repoRoot 'functions/private/Invoke-WinUtilMaintenanceInstall.ps1') -Raw
        $account | Should -Not -Match 'Register-ScheduledTask|Remove-AppxPackage|AsPlainText|local@2019|abc123'
        $install | Should -Not -Match 'New-LocalUser|Set-LocalUser|Rename-Computer|Start-Transcript|SourceFolder|@@'
        $account | Should -Match '\[securestring\]\$EmployeePassword'
    }

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
        Import-MaintenanceFunction 'winutil.ps1' 'ConvertTo-EmployeeName'
        $vietnameseName = [string][char]0x110 + 'ang ' + [char]0x110 + 'inh ' + [char]0x110 + 'uc'
        ConvertTo-EmployeeName $vietnameseName | Should -Be 'dangdinhduc'
    }
}

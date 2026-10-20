BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    . (Join-Path $script:repoRoot 'functions/private/Install-WinUtilOriginalMaintenanceFiles.ps1')
    . (Join-Path $script:repoRoot 'functions/private/Invoke-WinUtilOriginalMaintenance.ps1')
    . (Join-Path $script:repoRoot 'functions/private/Get-WinUtilOriginalMaintenanceStatus.ps1')
    . (Join-Path $script:repoRoot 'functions/private/Invoke-WinUtilMaintenance.ps1')
    function Write-WinUtilLog { param($Message,$Level,$Component) }
    function Set-Acl { param($LiteralPath,$AclObject) }
}

Describe 'Original maintenance files' {
    BeforeEach {
        $script:sync = @{ configs = @{ maintenanceOriginalFiles = [pscustomobject]@{}; maintenanceScripts = @{} } }
        foreach ($file in Get-ChildItem (Join-Path $script:repoRoot 'maintenance/original') -File) {
            $sync.configs.maintenanceOriginalFiles | Add-Member NoteProperty $file.Name ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName)))
        }
        $sync.configs.maintenanceScripts.RunOriginal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content (Join-Path $script:repoRoot 'maintenance/RunOriginal.ps1') -Raw -Encoding UTF8)))
        Mock Write-WinUtilLog {}
        Mock Set-Acl {}
    }

    It 'writes all four original files byte-for-byte and preserves replaced files' {
        $destination = Join-Path $TestDrive 'IT-MAINTENANCE'
        New-Item -ItemType Directory -Path $destination | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'CLEANER.bat') -Value 'previous cleaner'
        Install-WinUtilOriginalMaintenanceFiles -Destination $destination

        foreach ($file in Get-ChildItem (Join-Path $script:repoRoot 'maintenance/original') -File) {
            [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $destination $file.Name))) | Should -BeExactly ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName)))
        }
        @(Get-ChildItem (Join-Path $destination 'Backup') -Filter CLEANER.bat -Recurse).Count | Should -Be 1
        Get-Content (Get-ChildItem (Join-Path $destination 'Backup') -Filter CLEANER.bat -Recurse).FullName | Should -Be 'previous cleaner'
        Test-Path (Join-Path $destination 'RunOriginal.ps1') | Should -BeTrue
        Should -Invoke Set-Acl -Times 1 -Exactly -ParameterFilter { $AclObject.AreAccessRulesProtected }
    }

    It 'fails before writing anything when a compiled payload is missing' {
        $sync.configs.maintenanceOriginalFiles.PSObject.Properties.Remove('CLEANER.bat')
        $destination = Join-Path $TestDrive 'missing-payload'
        { Install-WinUtilOriginalMaintenanceFiles -Destination $destination } | Should -Throw '*Missing embedded*'
        Test-Path $destination | Should -BeFalse
        Should -Not -Invoke Set-Acl
    }

    It 'embeds original files without text conversion and exposes the compact controls' {
        Push-Location $script:repoRoot
        try { & ./Compile.ps1 } finally { Pop-Location }
        $compiled = Get-Content (Join-Path $script:repoRoot 'winutil.ps1') -Raw
        $match = [regex]::Match($compiled, "(?s)\`$sync\.configs\.maintenanceOriginalFiles = @'\r?\n(?<json>.*?)\r?\n'@ \| ConvertFrom-Json")
        $match.Success | Should -BeTrue
        $payloads = $match.Groups['json'].Value | ConvertFrom-Json
        foreach ($file in Get-ChildItem (Join-Path $script:repoRoot 'maintenance/original') -File) {
            $payloads.($file.Name) | Should -BeExactly ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName)))
        }
        $config = Get-Content (Join-Path $script:repoRoot 'config/maintenance.json') -Raw | ConvertFrom-Json
        $controls = @($config.PSObject.Properties | Where-Object { $_.Value.Category -eq 'IT-MAINTENANCE' } | Sort-Object { $_.Value.Order })
        $controls.Count | Should -Be 6
        @($controls | ForEach-Object { $_.Name }) | Should -Be @(
            'WPFToggleMaintenanceTasks',
            'WPFToggleMaintenanceMonitor',
            'WPFMaintenanceExportInventory',
            'WPFToggleWindowsUpdate',
            'WPFMaintenanceTaskScheduler',
            'WPFFixesWinget'
        )
        @($controls | ForEach-Object { $_.Value.Order }) | Should -Be @(1,2,3,4,5,6)
    }

    It 'runs a text workflow without requiring a console pause: <Action>' -TestCases @(
        @{ Action='Inventory'; File='GET-INFOMATION.txt' }
        @{ Action='Monitor'; File='IT-MAINTENANCE.txt' }
    ) {
        param([string]$Action,[string]$File)
        $runner = Join-Path $TestDrive 'RunOriginal.ps1'
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'maintenance/RunOriginal.ps1') -Destination $runner -Force
        $marker = Join-Path $TestDrive 'completed.txt'
        "Clear-Host`nRead-Host 'Press Enter to close'`nSet-Content -LiteralPath '$marker' -Value 'completed'" |
            Set-Content -LiteralPath (Join-Path $TestDrive $File)

        & $runner -Action $Action

        Get-Content -LiteralPath $marker | Should -Be 'completed'
    }
}

Describe 'Original maintenance actions' {
    BeforeEach {
        Mock Install-WinUtilOriginalMaintenanceFiles {}
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
        Mock Stop-ScheduledTask {}
        Mock Unregister-ScheduledTask {}
        Mock Test-Path { $true }
        Mock Start-Sleep {}
    }

    It 'creates and verifies exactly the two original daily tasks' {
        Invoke-WinUtilOriginalMaintenance -Action InstallTasks | Should -Match 'Verified IT-SHUTDOWN.*IT-CLEAN'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*schtasks.exe' -and $ArgumentList -like '*/TN "IT-SHUTDOWN"*' -and
            $ArgumentList -like '*/TR "C:\Windows\System32\shutdown.exe -s -t 600"*' -and $ArgumentList -like '*/ST 21:30 /F'
        }
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*schtasks.exe' -and $ArgumentList -like '*/TN "IT-CLEAN"*' -and
            $ArgumentList -like '*/TR "C:\IT-MAINTENANCE\CLEANER.bat -s -t 600"*' -and $ArgumentList -like '*/ST 12:30 /F'
        }
        Should -Invoke Get-ScheduledTask -Times 2 -Exactly -ParameterFilter { $TaskPath -eq '\' }
    }

    It 'does not report success when task creation fails' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
        { Invoke-WinUtilOriginalMaintenance -Action InstallTasks } | Should -Throw '*schtasks exit code 1*'
        Should -Not -Invoke Get-ScheduledTask
    }

    It 'does not report success when a task cannot be found after creation' {
        Mock Get-ScheduledTask { $null }
        { Invoke-WinUtilOriginalMaintenance -Action InstallTasks } | Should -Throw '*not created/enabled*'
    }

    It 'removes both daily tasks without redeploying files' {
        $script:taskNames = [Collections.Generic.HashSet[string]]::new([string[]]@('IT-SHUTDOWN','IT-CLEAN'))
        Mock Get-ScheduledTask {
            if ($script:taskNames.Contains($TaskName)) { [pscustomobject]@{ State = 'Ready' } }
        }
        Mock Unregister-ScheduledTask { [void]$script:taskNames.Remove($TaskName) }
        Invoke-WinUtilOriginalMaintenance -Action RemoveTasks | Should -Match 'Removed IT-SHUTDOWN and IT-CLEAN'
        Should -Invoke Unregister-ScheduledTask -Times 2 -Exactly
        Should -Not -Invoke Install-WinUtilOriginalMaintenanceFiles
    }

    It 'stops a running monitor before deleting its task' {
        $script:monitorExists = $true
        Mock Get-ScheduledTask {
            if ($script:monitorExists) { [pscustomobject]@{ State = 'Running' } }
        }
        Mock Unregister-ScheduledTask { $script:monitorExists = $false }
        Invoke-WinUtilOriginalMaintenance -Action RemoveMonitor | Should -Match 'Removed IT-MAINTENANCE'
        Should -Invoke Stop-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'IT-MAINTENANCE' }
        Should -Invoke Unregister-ScheduledTask -Times 1 -Exactly
    }

    It 'reports switch state from the installed tasks' {
        Get-WinUtilOriginalMaintenanceStatus -Status Tasks | Should -BeTrue
        Get-WinUtilOriginalMaintenanceStatus -Status Monitor | Should -BeTrue
        Mock Get-ScheduledTask {
            if ($TaskName -eq 'IT-CLEAN') { return $null }
            [pscustomobject]@{ State = 'Ready' }
        }
        Get-WinUtilOriginalMaintenanceStatus -Status Tasks | Should -BeFalse
    }

    It 'runs and verifies the original disk monitoring installer' {
        Invoke-WinUtilOriginalMaintenance -Action InstallMonitor | Should -Match '09:00 and 14:00 Monday-Friday'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*WindowsPowerShell*v1.0*powershell.exe' -and $ArgumentList -like '*RunOriginal.ps1" -Action Monitor' -and $Wait -and $WindowStyle -eq 'Hidden'
        }
        Should -Invoke Get-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'IT-MAINTENANCE' }
    }

    It 'fails if the monitoring installer did not create its script or configuration' {
        Mock Test-Path { $false }
        { Invoke-WinUtilOriginalMaintenance -Action InstallMonitor } | Should -Throw '*configuration is missing*'
    }

    It 'propagates original script failures' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
        { Invoke-WinUtilOriginalMaintenance -Action ExportInventory } | Should -Throw '*exit code 1*'
    }

    It 'exports reports immediately and verifies both fresh files and CSV columns' {
        Mock Get-Item { [pscustomobject]@{ LastWriteTime = (Get-Date).AddSeconds(5); Length = 2000 } }
        Mock Import-Csv { [pscustomobject]@{ PhanMem='Windows'; PhienBan='1'; NhaPhatHanh='Microsoft'; NgayCaiDat=''; LicenseStatus='Licensed' } }
        Invoke-WinUtilOriginalMaintenance -Action ExportInventory | Should -Match 'Reports created now \(no restart required\)'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -like '*RunOriginal.ps1" -Action Inventory' }
        Should -Not -Invoke Get-ScheduledTask
        Should -Invoke Import-Csv -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq "C:\IT-MAINTENANCE\$env:COMPUTERNAME.csv" }
    }

    It 'rejects stale CSV reports instead of claiming an old file is new' {
        Mock Get-Item {
            $date = if ($LiteralPath -like '*.csv') { (Get-Date).AddDays(-1) } else { (Get-Date).AddSeconds(5) }
            [pscustomobject]@{ LastWriteTime = $date; Length = 2000 }
        }
        { Invoke-WinUtilOriginalMaintenance -Action ExportInventory } | Should -Throw '*not produced*'
    }

    It 'rejects reports with missing software columns' {
        Mock Get-Item { [pscustomobject]@{ LastWriteTime = (Get-Date).AddSeconds(5); Length = 2000 } }
        Mock Import-Csv { [pscustomobject]@{ Unexpected='column' } }
        { Invoke-WinUtilOriginalMaintenance -Action ExportInventory } | Should -Throw '*missing expected columns*'
    }

    It 'routes the requested workflow through the existing background dispatcher' {
        Mock Invoke-WinUtilOriginalMaintenance { 'done' }
        Invoke-WinUtilMaintenance -Action ExportInventory | Should -Be 'done'
        Should -Invoke Invoke-WinUtilOriginalMaintenance -Times 1 -Exactly -ParameterFilter { $Action -eq 'ExportInventory' }
    }
}

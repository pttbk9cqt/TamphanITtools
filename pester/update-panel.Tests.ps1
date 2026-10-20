BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    . (Join-Path $repoRoot 'functions/public/Invoke-WPFUpdatePanel.ps1')
    . (Join-Path $repoRoot 'functions/public/Invoke-WPFButton.ps1')
    function Write-WinUtilLog { param($Component,$Level,$Message) }
    function Show-WinUtilMessage { param($Title,$Message,$Icon) }
    function Set-WinUtilTweaksProgressIndicator { param($Visible) }
}

Describe 'Update tab shortcuts' {
    BeforeEach {
        $script:sync = @{ configs = @{ maintenance = [pscustomobject]@{} }; ProcessRunning = $false }
        Mock Start-Process {}
        Mock Write-WinUtilLog {}
        Mock Show-WinUtilMessage {}
        Mock Set-WinUtilTweaksProgressIndicator {}
    }

    It 'opens Windows Update Settings without changing settings' {
        Invoke-WPFButton -Button WPFOpenWindowsUpdate
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'ms-settings:windowsupdate' }
    }

    It 'opens Store directly at Downloads instead of its homepage' {
        Invoke-WPFButton -Button WPFOpenStoreDownloads
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'ms-windows-store://downloadsandupdates' }
    }

    It 'reports an unavailable application' {
        Mock Start-Process { throw 'protocol unavailable' }
        Invoke-WPFUpdatePanel -Target StoreDownloads
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Icon -eq 'Error' -and $Message -like '*protocol unavailable*' }
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'ERROR' }
    }

    It 'provides equivalent Windows Update switches in both tabs' {
        $maintenance = Get-Content (Join-Path $repoRoot 'config/maintenance.json') -Raw | ConvertFrom-Json
        $update = Get-Content (Join-Path $repoRoot 'config/update.json') -Raw | ConvertFrom-Json
        $maintenance.WPFToggleMaintenanceWindowsUpdate.Status | Should -Be 'WindowsUpdate'
        $maintenance.WPFToggleMaintenanceWindowsUpdate.Description | Should -Be $update.WPFToggleWindowsUpdate.Description
        $update.WPFToggleWindowsUpdate.Type | Should -Be 'MaintenanceToggle'
        $update.WPFToggleWindowsUpdate.Status | Should -Be 'WindowsUpdate'
        $update.PSObject.Properties.Name.Count | Should -Be 3
    }
}

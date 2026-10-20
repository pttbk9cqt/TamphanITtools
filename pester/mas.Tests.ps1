BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    . (Join-Path $repoRoot 'functions/public/Invoke-WPFMAS.ps1')
    . (Join-Path $repoRoot 'functions/public/Invoke-WPFButton.ps1')
    . (Join-Path $repoRoot 'functions/public/Invoke-WPFTab.ps1')
    function Show-MASLaunchError { param($Message) }
    function Show-WinUtilMessage { param($Message,$Title,$Button,$Icon) }
    function Write-WinUtilLog { param($Message,$Level,$Component) }
    function Set-WinUtilTweaksProgressIndicator { param($Visible,$Label,$Percent) }
}

Describe 'Microsoft Activation Scripts launcher' {
    BeforeEach {
        $script:sync = [hashtable]::Synchronized(@{ ProcessRunning = $false; configs = @{ maintenance = [pscustomobject]@{} } })
        $script:launchCommand = $null
        Mock Show-WinUtilMessage {}
        Mock Write-WinUtilLog {}
        Mock Set-WinUtilTweaksProgressIndicator {}
        Mock Show-MASLaunchError {}
        Mock Start-Process {
            $script:launchCommand = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))
            [pscustomobject]@{ Id = 1234 }
        }
    }

    It 'opens MAS directly from Activation navigation without a second button' {
        Mock Invoke-WPFMAS {}
        Mock Invoke-WPFTab {}
        Invoke-WPFButton -Button WPFTab3BT
        Should -Invoke Invoke-WPFTab -Times 1 -Exactly -ParameterFilter { $ClickedTab -eq 'WPFTab3BT' }
        Should -Invoke Invoke-WPFMAS -Times 1 -Exactly
        $config = Get-Content (Join-Path $repoRoot 'config/tweaks.json') -Raw | ConvertFrom-Json
        $config.PSObject.Properties.Name | Should -Not -Contain 'WPFMASbutton'
        [xml]$xaml = Get-Content (Join-Path $repoRoot 'xaml/inputXML.xaml') -Raw
        $tab = $xaml.SelectSingleNode('//*[local-name()="TabItem"][@Header="Activation"]')
        $tab.GetAttribute('Name') | Should -Be 'WPFTab3'
        $tab.SelectSingleNode('.//*[local-name()="Button"]') | Should -BeNullOrEmpty
        $config.PSObject.Properties.Name | Should -Not -Contain 'WPFOOSUbutton'
    }

    It 'does not launch MAS from other navigation buttons' {
        Mock Invoke-WPFMAS {}
        Mock Invoke-WPFTab {}
        foreach ($button in 'WPFTab1BT','WPFTab2BT','WPFTab4BT','WPFTab5BT','WPFTab6BT') {
            Invoke-WPFButton -Button $button
        }
        Should -Not -Invoke Invoke-WPFMAS
        Should -Invoke Invoke-WPFTab -Times 5 -Exactly
    }

    It 'launches directly through navigation while retaining the busy guard' {
        Mock Invoke-WPFTab {}
        Invoke-WPFButton -Button WPFTab3BT
        Should -Invoke Start-Process -Times 1 -Exactly
        $sync.ProcessRunning = $true
        Invoke-WPFButton -Button WPFTab3BT
        Should -Invoke Start-Process -Times 1 -Exactly
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Icon -eq 'Warning' }
    }

    It 'hides the bootstrap console without blocking the external MAS menu' {
        Invoke-WPFMAS
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*WindowsPowerShell\v1.0\powershell.exe' -and
            $WindowStyle -eq 'Hidden' -and -not $Wait -and
            $ArgumentList -contains '-NoProfile' -and $ArgumentList -notcontains '-NoExit' -and
            $ArgumentList -contains '-EncodedCommand' -and $PassThru
        }
        $launchCommand | Should -Match 'irm https://get\.activated\.win \| iex'
        $launchCommand | Should -Match 'Tls12'
        $launchCommand | Should -Not -Match 'WindowTitle'
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($launchCommand,[ref]$null,[ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
        $sync.ProcessRunning | Should -BeFalse
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Message -like '*PID 1234*' }
    }

    It 'does not launch while another WinUtil workflow is busy' {
        $sync.ProcessRunning = $true
        Invoke-WPFMAS
        Should -Not -Invoke Start-Process
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Icon -eq 'Warning' }
        $sync.ProcessRunning | Should -BeTrue
    }

    It 'reports process launch failures without leaving WinUtil busy' {
        Mock Start-Process { throw 'launch failed' }
        Invoke-WPFMAS
        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Message -like '*launch failed*' -and $Icon -eq 'Error' }
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'ERROR' }
        $sync.ProcessRunning | Should -BeFalse
    }

    It 'handles download errors in the child command without contacting the live endpoint' {
        Invoke-WPFMAS
        Mock Invoke-RestMethod { throw 'simulated network failure' }
        Mock Write-Host {}
        # Execute only the try/catch, leaving console and TLS setup to the real child process.
        $body = $launchCommand.Substring($launchCommand.IndexOf('try {'))
        & ([scriptblock]::Create($body))
        Should -Invoke Show-MASLaunchError -Times 1 -Exactly -ParameterFilter { $Message -like '*simulated network failure*' }
    }

    It 'executes the requested pipeline with a harmless downloaded script fixture' {
        Invoke-WPFMAS
        Mock Invoke-RestMethod { "Write-Output 'MAS fixture reached'" }
        $body = $launchCommand.Substring($launchCommand.IndexOf('try {'))
        & ([scriptblock]::Create($body)) | Should -Be 'MAS fixture reached'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://get.activated.win' }
    }

    It 'runs the encoded command in Windows PowerShell with a safe <Scenario> fixture' -TestCases @(
        @{ Scenario = 'success'; Download = "return `"Write-Output 'MAS child fixture reached'`""; Expected = 'MAS child fixture reached' },
        @{ Scenario = 'failure'; Download = "throw 'simulated child network failure'"; Expected = 'Unable to launch Microsoft Activation Scripts: simulated child network failure' }
    ) {
        param($Scenario,$Download,$Expected)
        Invoke-WPFMAS
        # Override the download inside the child process: no live remote code is fetched or run.
        $fixture = "function Invoke-RestMethod { param(`$Uri) $Download }`n" + $launchCommand.Replace("try {", "function Show-MASLaunchError { param(`$Message) Write-Output `$Message }; try {")
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($fixture))
        $console = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # Match the launcher lifecycle: no -NoExit, so the bootstrap console can finish.
        $output = & $console -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match ([regex]::Escape($Expected))
    }
}

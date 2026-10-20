BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:launcherPath = Join-Path $repoRoot 'TamphanITtools.cmd'
    $script:launcherText = Get-Content -LiteralPath $launcherPath -Raw
    $script:payload = ($launcherText -split '(?m)^# POWERSHELL_PAYLOAD\r?$', 2)[1]
    $script:payloadAst = [Management.Automation.Language.Parser]::ParseInput($payload, [ref]$null, [ref]$null)
    $functionAst = $payloadAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] }
    . ([scriptblock]::Create($functionAst.Extent.Text))
}

Describe 'TamphanITtools launcher' {
    BeforeEach {
        $script:fixtureRoot = Join-Path $TestDrive "USB user's folder"
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'winutil.ps1') -Value "Write-Output 'safe fixture'"
        $script:downloadFolder = $null
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Invoke-RestMethod { throw 'Unexpected network request in launcher tests' }
        Mock Invoke-WebRequest {
            $script:downloadFolder = Split-Path -Path $OutFile -Parent
            if ($Uri -like '*.sha256') {
                $hash = (Get-FileHash -LiteralPath (Join-Path $downloadFolder 'winutil.ps1') -Algorithm SHA256).Hash
                Set-Content -LiteralPath $OutFile -Value $hash
            } else {
                Set-Content -LiteralPath $OutFile -Value "Write-Output 'download fixture'"
            }
        }
    }

    It 'contains a valid PowerShell payload' {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($payload, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'preserves apostrophes in local paths and parameters when building the elevation command' {
        $startText = Get-Content (Join-Path $repoRoot 'scripts/start.ps1') -Raw
        $offset = $startText.IndexOf('    $argList = @()')
        $end = $startText.IndexOf('    $powershellCmd =', $offset)
        # Created scriptblocks reset PowerShell's automatic path/bound-parameter variables.
        # Substitute only those variable names so the fixture exercises the actual command builder.
        $buildCommand = $startText.Substring($offset, $end - $offset).Replace('$PSCommandPath', '$fixtureCommandPath').Replace('$PSBoundParameters', '$fixtureBoundParameters')
        $fixturePath = Join-Path $fixtureRoot 'winutil.ps1'
        Set-Content -LiteralPath $fixturePath -Value 'param([string]$Config,[switch]$Offline) Write-Output "$Config|$Offline"'
        $command = & {
            param($Code,$File)
            $fixtureCommandPath = $File
            $fixtureBoundParameters = @{ Config = "user's config.json"; Offline = [switch]$true }
            . ([scriptblock]::Create($Code))
            $script
        } $buildCommand $fixturePath
        & ([scriptblock]::Create($command)) | Should -Be "user's config.json|True"
        $startText | Should -Match 'EncodedCommand'
        $startText | Should -Not -Match 'github.com/ChrisTitusTech/winutil/releases'
        $startText | Should -Match 'github.com/pttbk9cqt/TamphanITtools/releases/latest/download/winutil.ps1'
    }

    It 'runs an offline USB copy with quoted paths and no downloads or automatic operations' {
        Invoke-TamphanLauncher -Root $fixtureRoot -Offline
        Should -Not -Invoke Invoke-WebRequest
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $Verb -eq 'RunAs' -and $Wait -and $PassThru -and
            $FilePath -like '*WindowsPowerShell\v1.0\powershell.exe' -and
            $ArgumentList -eq ('-NoProfile -STA -ExecutionPolicy Bypass -File "' + (Join-Path $fixtureRoot 'winutil.ps1') + '" -Offline')
        }
        Test-Path -LiteralPath (Join-Path $fixtureRoot 'winutil.ps1') | Should -BeTrue
    }

    It 'fails clearly when the USB script is absent' {
        { Invoke-TamphanLauncher -Root $TestDrive -Offline } | Should -Throw '*requires winutil.ps1*'
        Should -Not -Invoke Start-Process
        Should -Not -Invoke Invoke-WebRequest
    }

    It 'downloads only from this repo and verifies the checksum before elevation' {
        Invoke-TamphanLauncher -Root $fixtureRoot
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://github.com/pttbk9cqt/TamphanITtools/releases/latest/download/winutil.ps1'
        }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://github.com/pttbk9cqt/TamphanITtools/releases/latest/download/winutil.ps1.sha256'
        }
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $Verb -eq 'RunAs' -and $ArgumentList -notmatch ' -Offline| -Preset| -Config'
        }
        Test-Path -LiteralPath $downloadFolder | Should -BeFalse
    }

    It 'does not execute partial downloads or silently run a local fallback' {
        Mock Invoke-WebRequest { throw 'network unavailable' }
        { Invoke-TamphanLauncher -Root $fixtureRoot } | Should -Throw '*network unavailable*'
        Should -Not -Invoke Start-Process
    }

    It 'rejects a mismatched checksum and cleans only its download directory' {
        Mock Invoke-WebRequest {
            $script:downloadFolder = Split-Path -Path $OutFile -Parent
            if ($Uri -like '*.sha256') { Set-Content -LiteralPath $OutFile -Value ('0' * 64) }
            else { Set-Content -LiteralPath $OutFile -Value "Write-Output 'fixture'" }
        }
        { Invoke-TamphanLauncher -Root $fixtureRoot } | Should -Throw '*checksum does not match*'
        Should -Not -Invoke Start-Process
        Test-Path -LiteralPath $downloadFolder | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixtureRoot 'winutil.ps1') | Should -BeTrue
    }

    It 'rejects an invalid checksum response' {
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value '<html>Not found</html>' }
        { Invoke-TamphanLauncher -Root $fixtureRoot } | Should -Throw '*checksum is invalid*'
        Should -Not -Invoke Start-Process
    }

    It 'rejects invalid PowerShell before elevation' {
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'winutil.ps1') -Value 'function {'
        { Invoke-TamphanLauncher -Root $fixtureRoot -Offline } | Should -Throw '*invalid PowerShell syntax*'
        Should -Not -Invoke Start-Process
    }

    It 'reports cancelled UAC without retrying or downloading another tool' {
        Mock Start-Process { throw 'The operation was canceled by the user' }
        { Invoke-TamphanLauncher -Root $fixtureRoot -Offline } | Should -Throw '*canceled*'
        Should -Invoke Start-Process -Times 1 -Exactly
        Should -Not -Invoke Invoke-WebRequest
    }

    It 'reports a failed tool process' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
        { Invoke-TamphanLauncher -Root $fixtureRoot -Offline } | Should -Throw '*exited with code 1*'
    }

    It 'runs the real CMD entrypoint in Windows PowerShell with a missing offline file' {
        $cmdPath = Join-Path $fixtureRoot 'TamphanITtools.cmd'
        Copy-Item -LiteralPath $launcherPath -Destination $cmdPath
        Remove-Item -LiteralPath (Join-Path $fixtureRoot 'winutil.ps1')
        # Feed PAUSE a newline. Missing-file validation exits before any UAC or tool execution.
        Push-Location -LiteralPath $fixtureRoot
        try {
            $output = "" | & $env:ComSpec /d /c 'TamphanITtools.cmd offline' 2>&1
        } finally {
            Pop-Location
        }
        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'Offline mode requires winutil.ps1'
        Should -Not -Invoke Start-Process
    }
}

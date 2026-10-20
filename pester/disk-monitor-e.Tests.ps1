BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $installer = Get-Content (Join-Path $repoRoot 'maintenance/original/IT-MAINTENANCE.txt') -Raw -Encoding UTF8
    $installerAst = [Management.Automation.Language.Parser]::ParseInput($installer,[ref]$null,[ref]$null)
    $assignment = $installerAst.Find({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.VariablePath.UserPath -eq 'ScriptContent'
    },$true)
    $script:monitorBody = $assignment.Right.Expression.Value
    $monitorAst = [Management.Automation.Language.Parser]::ParseInput($monitorBody,[ref]$null,[ref]$null)
    $diskInfo = $monitorAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ITDiskInfo' },$true)
    . ([scriptblock]::Create($diskInfo.Extent.Text))
    $start = $monitorBody.IndexOf('    # E: is optional')
    $end = $monitorBody.IndexOf('    if (-not (Test-Path $ConfigFile))', $start)
    $script:eWarning = [scriptblock]::Create($monitorBody.Substring($start,$end-$start))
    function Write-ITLog { param($Status,$Message) }
    function Show-UserMessage { param($Message) }
}

Describe 'Optional E drive warnings' {
    BeforeEach {
        $script:WarningGB = 30
        $script:HideGB = 20
        Mock Get-CimInstance { [pscustomobject]@{ Capacity = 100GB; FreeSpace = 25GB } }
        Mock Write-ITLog {}
        Mock Show-UserMessage {}
    }
    It 'parses the deployed monitor as valid PowerShell' {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($monitorBody,[ref]$null,[ref]$errors)
        $errors.Count | Should -Be 0
    }
    It 'warns for E: with <Free> GB remaining' -TestCases @(@{Free=30},@{Free=20},@{Free=5}) {
        param($Free)
        Mock Get-CimInstance { [pscustomobject]@{ Capacity = 100GB; FreeSpace = ($Free * 1GB) } }
        & $eWarning
        Should -Invoke Show-UserMessage -Times 1 -Exactly -ParameterFilter { $Message -like '*O DIA E:*' -and $Message -like '*KHONG AN O E:*' }
        Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter { $Filter -eq "DriveLetter='E:'" }
    }
    It 'does not warn when E: has more than 30 GB free' {
        Mock Get-CimInstance { [pscustomobject]@{ Capacity = 100GB; FreeSpace = 31GB } }
        & $eWarning
        Should -Not -Invoke Show-UserMessage
    }
    It 'skips an absent E: without failing D: monitoring' {
        Mock Get-CimInstance { $null }
        { & $eWarning } | Should -Not -Throw
        Should -Not -Invoke Show-UserMessage
    }
    It 'logs unreadable E: capacity and contains no destructive commands' {
        Mock Get-CimInstance { [pscustomobject]@{ Capacity = 0; FreeSpace = 0 } }
        & $eWarning
        Should -Invoke Write-ITLog -Times 1 -Exactly -ParameterFilter { $Status -eq 'LOI E' }
        $eWarning.ToString() | Should -Not -Match 'Invoke-ITDiskPart|Remove-Item|Set-Partition|Start-Process'
    }
}

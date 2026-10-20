Describe 'Windows Update real WPF/runspace responsiveness' {
    It 'keeps a real dispatcher responsive across initial refresh and repeated off/on cycles using harmless service fixtures' {
        $fixture = Join-Path $PSScriptRoot 'fixtures/WindowsUpdateResponsive.ps1'
        $powershellPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = & $powershellPath -NoProfile -STA -ExecutionPolicy Bypass -File $fixture 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output | Out-String)
        ($output | Out-String) | Should -Match 'PASS: real WPF dispatcher and real runspaces remained responsive'
    }
}

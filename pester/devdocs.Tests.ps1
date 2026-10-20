BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

Describe 'Maintenance reference generation' {
    It 'generates retained tool pages from maintenance config without feature.json' {
        # Exercise the generator in an isolated fixture, never in the real generated directories.
        foreach ($folder in @('tools','config','functions/public','functions/private')) {
            New-Item -ItemType Directory -Path (Join-Path $TestDrive $folder) -Force | Out-Null
        }
        Copy-Item (Join-Path $repoRoot 'tools/devdocs-generator.ps1') (Join-Path $TestDrive 'tools')
        Copy-Item (Join-Path $repoRoot 'config/maintenance.json') (Join-Path $TestDrive 'config')
        Copy-Item (Join-Path $repoRoot 'config/tweaks.json') (Join-Path $TestDrive 'config')
        foreach ($name in @('Invoke-WPFButton.ps1','Invoke-WPFFixesWinget.ps1')) {
            Copy-Item (Join-Path $repoRoot "functions/public/$name") (Join-Path $TestDrive 'functions/public')
        }

        & (Join-Path $TestDrive 'tools/devdocs-generator.ps1')

        $output = Join-Path $TestDrive 'docs/src/content/docs/code-reference/features'
        @(Get-ChildItem $output -Recurse -Filter *.mdx).Count | Should -Be 15
        $winget = Get-Content (Join-Path $output 'fixes/winget.mdx') -Raw
        $winget | Should -Match 'function Invoke-WPFFixesWinget'
        $panel = Get-Content (Join-Path $output 'legacy-windows-panels/control.mdx') -Raw
        $panel | Should -Match 'config/maintenance.json'
        $panel | Should -Match '"control"'
        Test-Path (Join-Path $TestDrive 'config/feature.json') | Should -BeFalse
        @(Get-ChildItem $output -Recurse -Filter *.mdx | Where-Object Name -Match 'PSProfile|SSH|hyperv|Sandbox').Count | Should -Be 0
    }
}

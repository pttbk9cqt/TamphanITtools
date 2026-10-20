BeforeAll {
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

Describe 'Retired runtime components' {
    It 'keeps only renderer types present in the active catalogs' {
        $types = foreach ($name in 'appnavigation','appx','tweaks','maintenance','update') {
            $config = Get-Content "$script:root/config/$name.json" -Raw | ConvertFrom-Json
            $config.PSObject.Properties.Value | ForEach-Object { $_.Type }
        }
        $types | Should -Not -Contain ToggleButton
        $source = Get-Content "$script:root/functions/public/Invoke-WPFUIElements.ps1" -Raw
        $source | Should -Not -Match '"ToggleButton"\s*\{'
        $source | Should -Not -Match '\$count\+\+'
        $types | Should -Contain Combobox
        $types | Should -Contain RadioButton
    }

    It 'does not embed unused styles or FOSS metadata' {
        [xml]$xaml = Get-Content "$script:root/xaml/inputXML.xaml" -Raw
        $keys = @($xaml.SelectNodes('//*[@*[local-name()="Key"]]') | ForEach-Object {
            $_.GetAttribute('Key','http://schemas.microsoft.com/winfx/2006/xaml')
        })
        foreach ($key in 'FilterChipStyle','labelfortweaks','ScrollVisibilityRectangle','ToggleButtonStyle') {
            $keys | Should -Not -Contain $key
        }
        $apps = Get-Content "$script:root/config/applications.json" -Raw | ConvertFrom-Json
        foreach ($app in $apps.PSObject.Properties.Value) {
            $app.PSObject.Properties.Name | Should -Not -Contain foss
        }
    }

    It 'does not retain Notepad-specific process termination in AppX removal' {
        $source = Get-Content "$script:root/functions/public/Invoke-WPFAppxRemoval.ps1" -Raw
        $source | Should -Not -Match 'WindowsNotepad|dllhost'
    }
}

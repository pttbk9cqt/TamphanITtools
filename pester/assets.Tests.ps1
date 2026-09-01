#===========================================================================
# Tests - Asset rendering
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

Describe "Rendered asset caching" {
    It "embeds the BECAMEX globe logo for standalone builds" {
        $brandLogoScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\New-WinUtilBecamexLogo.ps1") -Raw
        $taskbarIconScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\New-WinUtilBecamexTaskbarIcon.ps1") -Raw
        $assetScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilAssets.ps1") -Raw

        $brandLogoScript | Should -Match 'New-WinUtilBecamexLogo'
        $brandLogoScript | Should -Match 'gzip-compressed and embedded'
        $brandLogoScript | Should -Match '\$canvas\.Height = if \(\$FullArtwork\) \{ 444 \} else \{ 360 \}'
        $brandLogoScript | Should -Match '\[double\]\$Width = 0'
        $brandLogoScript | Should -Match '\[double\]\$Height = 0'
        $taskbarIconScript | Should -Match 'New-WinUtilBecamexTaskbarIcon'
        $brandLogoScript | Should -Match '\[switch\]\$FullArtwork'
        $taskbarIconScript | Should -Match 'New-WinUtilBecamexLogo -Width \$Size -Height \$Size -FullArtwork -Render:\$Render'
        $assetScript | Should -Match 'New-WinUtilBecamexLogo -Size \$Size -Render:\$render'
    }

    It "caches rendered bitmap assets by type and size" {
        $assetScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilAssets.ps1") -Raw

        $assetScript | Should -Match 'RenderedAssetCache'
        $assetScript | Should -Match '\$cacheKey = "\$\(\(\[string\]\$type\)\.ToLowerInvariant\(\)\)\|\$Size"'
        $assetScript | Should -Match 'return \$sync\.RenderedAssetCache\[\$cacheKey\]'
        $assetScript | Should -Match '\$sync\.RenderedAssetCache\[\$cacheKey\] = \$bitmapImage'
    }

    It "renders only the logo overlay before first paint and defers status overlays" {
        $mainScript = Get-Content -Path (Join-Path $script:repoRoot "scripts\main.ps1") -Raw

        $mainScript | Should -Match 'Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo \$true -IncludeStatusAssets \$false'
        $mainScript | Should -Match 'New-WinUtilBecamexLogo -Width 110 -Height 68'
        $mainScript | Should -Match 'Dispatcher\.BeginInvoke\(\[System\.Windows\.Threading\.DispatcherPriority\]::Background, \[action\]\{ Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo \$false -IncludeStatusAssets \$true \}'
        $mainScript | Should -Not -Match '\$sync\["checkmarkrender"\] = \(Invoke-WinUtilAssets -Type "checkmark"'
        $mainScript | Should -Not -Match '\$sync\["warningrender"\] = \(Invoke-WinUtilAssets -Type "warning"'
    }

    It "lazily creates taskbar overlays before assigning them" {
        $taskbarScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\Set-WinUtilTaskbarItem.ps1") -Raw
        $overlayAssetScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\Initialize-WinUtilTaskbarOverlayAssets.ps1") -Raw

        $taskbarScript | Should -Match 'Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo \$true -IncludeStatusAssets \$false'
        $taskbarScript | Should -Match 'Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo \$false -IncludeStatusAssets \$true'
        $overlayAssetScript | Should -Match 'New-WinUtilBecamexTaskbarIcon -Size 512 -Render'
    }

}

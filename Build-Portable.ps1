<#
.SYNOPSIS
    Compiles and packages the local portable tool; does not publish a release.
#>
$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    & ./Compile.ps1
    if (-not (Test-Path -LiteralPath './winutil.ps1' -PathType Leaf)) {
        throw 'Compilation did not produce winutil.ps1.'
    }
    $outputDirectory = Join-Path $PSScriptRoot 'binary'
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Copy-Item -LiteralPath './winutil.ps1' -Destination (Join-Path $outputDirectory 'winutil.ps1') -Force
    Copy-Item -LiteralPath './TamphanITtools.cmd' -Destination (Join-Path $outputDirectory 'TamphanITtools.cmd') -Force
    $hash = (Get-FileHash -LiteralPath './winutil.ps1' -Algorithm SHA256).Hash
    Set-Content -LiteralPath (Join-Path $outputDirectory 'winutil.ps1.sha256') -Value $hash -Encoding ASCII
    $files = @('TamphanITtools.cmd','winutil.ps1','winutil.ps1.sha256') | ForEach-Object { Join-Path $outputDirectory $_ }
    Compress-Archive -LiteralPath $files -DestinationPath (Join-Path $outputDirectory 'TamphanITtools-portable.zip') -Force
    Write-Host "Portable ZIP and release assets are ready in $outputDirectory. Nothing has been published."
} finally {
    Pop-Location
}

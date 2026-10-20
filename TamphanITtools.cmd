@echo off
setlocal DisableDelayedExpansion
set "TAMPHAN_LAUNCHER_PATH=%~f0"
set "TAMPHAN_LAUNCHER_OFFLINE="
if "%~1"=="" goto launch
if /I "%~1"=="offline" (
    set "TAMPHAN_LAUNCHER_OFFLINE=1"
    goto launch
)
echo Usage: TamphanITtools.cmd [offline]
exit /b 1
:launch
set "TAMPHAN_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "TAMPHAN_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%TAMPHAN_POWERSHELL%" -NoProfile -STA -ExecutionPolicy Bypass -Command "$text = Get-Content -LiteralPath $env:TAMPHAN_LAUNCHER_PATH -Raw; $body = ($text -split '(?m)^# POWERSHELL_PAYLOAD\r?$', 2)[1]; & ([scriptblock]::Create($body))"
set "TAMPHAN_EXIT_CODE=%ERRORLEVEL%"
if not "%TAMPHAN_EXIT_CODE%"=="0" pause
exit /b %TAMPHAN_EXIT_CODE%
# POWERSHELL_PAYLOAD
function Invoke-TamphanLauncher {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [switch]$Offline
    )

    $ErrorActionPreference = 'Stop'
    $downloadDirectory = $null
    try {
        if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
            throw 'PowerShell is restricted by organizational policy. Contact your administrator.'
        }

        if ($Offline) {
            $scriptPath = Join-Path $Root 'winutil.ps1'
            if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                throw 'Offline mode requires winutil.ps1 next to TamphanITtools.cmd. Use the portable ZIP.'
            }
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $downloadDirectory = Join-Path ([IO.Path]::GetTempPath()) ('TamphanITtools-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $downloadDirectory -ErrorAction Stop | Out-Null
            $scriptPath = Join-Path $downloadDirectory 'winutil.ps1'
            $checksumPath = Join-Path $downloadDirectory 'winutil.ps1.sha256'
            $releaseUrl = 'https://github.com/pttbk9cqt/TamphanITtools/releases/latest/download'
            Write-Host 'Downloading the latest TamphanITtools release...'
            Invoke-WebRequest -Uri "$releaseUrl/winutil.ps1" -OutFile $scriptPath -UseBasicParsing -TimeoutSec 120
            Invoke-WebRequest -Uri "$releaseUrl/winutil.ps1.sha256" -OutFile $checksumPath -UseBasicParsing -TimeoutSec 30
            $expectedHash = (Get-Content -LiteralPath $checksumPath -Raw).Trim()
            if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$') {
                throw 'The release checksum is invalid. Nothing was run.'
            }
            if ((Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash -ne $expectedHash) {
                throw 'The release checksum does not match. Nothing was run; try again after the release finishes uploading.'
            }
        }

        $syntaxErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$syntaxErrors)
        if ($syntaxErrors.Count -gt 0 -or (Get-Item -LiteralPath $scriptPath).Length -eq 0) {
            throw 'The script is empty or has invalid PowerShell syntax. Nothing was run.'
        }
        $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
            $powershellPath = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        }
        Write-Host 'Opening TamphanITtools. Approve the administrator prompt to continue.'
        $arguments = '-NoProfile -STA -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
        if ($Offline) { $arguments += ' -Offline' }
        $process = Start-Process -FilePath $powershellPath -ArgumentList $arguments -Verb RunAs -WindowStyle Normal -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -ne 0) {
            throw "TamphanITtools exited with code $($process.ExitCode)."
        }
    } finally {
        # Only remove the GUID directory created by this invocation, never the USB/source files.
        if ($downloadDirectory -and (Test-Path -LiteralPath $downloadDirectory)) {
            Remove-Item -LiteralPath $downloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

try {
    Invoke-TamphanLauncher -Root ([IO.Path]::GetDirectoryName($env:TAMPHAN_LAUNCHER_PATH)) -Offline:($env:TAMPHAN_LAUNCHER_OFFLINE -eq '1')
    exit 0
} catch {
    Write-Host ("Unable to start TamphanITtools: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Online mode needs a public stable release with winutil.ps1 and winutil.ps1.sha256.'
    Write-Host 'For USB/local use: TamphanITtools.cmd offline. If UAC was cancelled, run again and approve it.'
    exit 1
}

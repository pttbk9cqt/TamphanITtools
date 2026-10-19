param([Parameter(Mandatory)][ValidateSet('Inventory','Monitor')][string]$Action)

$ErrorActionPreference = 'Stop'
$file = if ($Action -eq 'Inventory') { 'GET-INFOMATION.txt' } else { 'IT-MAINTENANCE.txt' }
# The original monitor installer only uses Read-Host to pause before closing.
# The GUI supplies completion/error messages, so no console/ISE prompt is needed.
function Read-Host { param([string]$Prompt) return '' }
function Clear-Host { }
try {
    $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $file))
    & ([scriptblock]::Create($text))
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}

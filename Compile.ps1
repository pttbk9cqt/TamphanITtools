param (
    [switch]$Run
)

$OFS = "`r`n"

# Variable to sync between runspaces
$sync = [Hashtable]::Synchronized(@{})
$sync.configs = @{}

$script = (Get-Content -Path scripts\start.ps1) -replace '#{replaceme}', (Get-Date -Format 'yy.MM.dd')

$script += Get-ChildItem -Path functions -Recurse -File | ForEach-Object {
    Get-Content -Path $_.FullName -Raw
}

Get-ChildItem config | ForEach-Object {
    $obj = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json

    if ($_.Name -eq "applications.json") {
        $fixed = [ordered]@{}
        foreach ($p in $obj.PSObject.Properties) {
            $fixed["WPFInstall$($p.Name)"] = $p.Value
        }
        $obj = [pscustomobject]$fixed
    }

    $json = $obj | ConvertTo-Json -Depth 10

    $sync.configs[$_.BaseName] = $obj
    $script += "`$sync.configs.$($_.BaseName) = @'`r`n$json`r`n'@ | ConvertFrom-Json"
}

$maintenanceScripts = [ordered]@{}
Get-ChildItem -Path maintenance -Filter *.ps1 -File | ForEach-Object {
    $body = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    $maintenanceScripts[$_.BaseName] = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
}
$payloadJson = $maintenanceScripts | ConvertTo-Json
$script += "`$sync.configs.maintenanceScripts = @'`r`n$payloadJson`r`n'@ | ConvertFrom-Json"

$originalMaintenanceFiles = [ordered]@{}
Get-ChildItem -LiteralPath maintenance/original -File | ForEach-Object {
    $originalMaintenanceFiles[$_.Name] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
}
$originalPayloadJson = $originalMaintenanceFiles | ConvertTo-Json
$script += "`$sync.configs.maintenanceOriginalFiles = @'`r`n$originalPayloadJson`r`n'@ | ConvertFrom-Json"

$xaml = Get-Content -Path xaml\inputXML.xaml -Raw
$script += "`$inputXML = @'`r`n$xaml`r`n'@"

$script += Get-Content -Path scripts\main.ps1 -Raw

Set-Content -Path winutil.ps1 -Value $script -Encoding UTF8

if ($Run) {
    .\Winutil.ps1
}

. "$PSScriptRoot\Common.ps1"
$taskName = 'IT-INVENTORY-ONCE'
function Get-LicenseText($Value) {
    $labels = @('Unlicensed','Licensed','OOB Grace','OOT Grace','Non-Genuine Grace','Notification','Extended Grace')
    if ($null -eq $Value -or [int]$Value -lt 0 -or [int]$Value -ge $labels.Count) { return 'Unknown' }
    return $labels[[int]$Value]
}
function New-InventoryRow($Name,$Version,$Publisher,$Date,$License) {
    [pscustomobject]@{ PhanMem=$Name; PhienBan=$Version; NhaPhatHanh=$Publisher; NgayCaiDat=$Date; LicenseStatus=$License }
}
function Read-UninstallKeys([string]$Hive) {
    foreach ($suffix in @('Software\Microsoft\Windows\CurrentVersion\Uninstall\*','Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($app in @(Get-ItemProperty "$Hive\$suffix" -ErrorAction SilentlyContinue | Where-Object DisplayName)) {
            New-InventoryRow $app.DisplayName $app.DisplayVersion $app.Publisher $app.InstallDate 'Unknown / not reported'
        }
    }
}
try {
    $cfg = Get-Content -LiteralPath "$Root\SetupState.json" -Raw | ConvertFrom-Json
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    if ($boot.ToUniversalTime() -le [datetime]::Parse($cfg.SetupBootUtc).ToUniversalTime()) {
        Write-ITLog 'Waiting for the next restart.' 'Inventory.log'; exit 0
    }
    if ($env:COMPUTERNAME -ine $cfg.ExpectedComputerName) { throw 'Computer name does not match expected name after restart.' }
    $hostName = $env:COMPUTERNAME
    $csv = Join-Path $Root "$hostName.csv"
    $txt = Join-Path $Root "$hostName.txt"
    $os = Get-CimInstance Win32_OperatingSystem
    $licenses = @(Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue | Where-Object PartialProductKey)
    $win = @($licenses | Where-Object { $_.ApplicationID -eq '55c92734-d682-4d71-983e-d6ec3f16059f' } | Sort-Object @{Expression={ $_.LicenseStatus -eq 1 };Descending=$true})
    $status = 'Unknown'
    if ($win.Count) { $status = Get-LicenseText $win[0].LicenseStatus }
    $windowsRow = New-InventoryRow $os.Caption $os.Version $os.Manufacturer ($os.InstallDate.ToString('yyyy-MM-dd')) $status
    $apps = @(Read-UninstallKeys 'Registry::HKEY_LOCAL_MACHINE')
    foreach ($userProfile in @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.SID -match '^S-1-5-21-' })) {
        $mount = $userProfile.SID
        $loadedHere = $false
        try {
            if (-not (Test-Path "Registry::HKEY_USERS\$mount")) {
                $hive = Join-Path $userProfile.LocalPath 'NTUSER.DAT'
                if (-not (Test-Path -LiteralPath $hive)) { continue }
                $mount = 'ITInventory_' + [guid]::NewGuid().ToString('N')
                & reg.exe load "HKU\$mount" $hive 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { Write-ITLog "Cannot load profile $($userProfile.SID); per-user software incomplete." 'Inventory.log'; continue }
                $loadedHere = $true
            }
            $apps += @(Read-UninstallKeys "Registry::HKEY_USERS\$mount")
        } finally {
            if ($loadedHere) {
                [GC]::Collect(); [GC]::WaitForPendingFinalizers()
                & reg.exe unload "HKU\$mount" 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { Write-ITLog "Could not unload temporary hive $mount." 'Inventory.log' }
            }
        }
    }
    foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage })) {
        $apps += New-InventoryRow $pkg.Name $pkg.Version.ToString() $pkg.Publisher '' 'Unknown / not reported'
    }
    # Keep licensing entries separate. Never assign one Office license to every Office installation.
    $officeLicenses = @($licenses | Where-Object { $_.Name -match 'Office' })
    $officeLicenses += @(Get-CimInstance OfficeSoftwareProtectionProduct -ErrorAction SilentlyContinue | Where-Object PartialProductKey)
    foreach ($license in @($officeLicenses | Sort-Object ID -Unique)) {
        $apps += New-InventoryRow ("Microsoft Office license: " + $license.Name) '' 'Microsoft' '' (Get-LicenseText $license.LicenseStatus)
    }
    $sorted = @($apps | Sort-Object PhanMem,PhienBan -Unique | Sort-Object @{Expression={if ($_.PhanMem -match '(?i)Microsoft.*(Office|365)|Office.*Microsoft') {0} else {1}}},PhanMem)
    # Neutralize spreadsheet formula prefixes in text metadata before CSV export.
    $rows = @($windowsRow) + $sorted
    foreach ($row in $rows) {
        foreach ($prop in $row.PSObject.Properties) {
            if ($prop.Value -is [string] -and $prop.Value -match '^\s*[=+@-]') { $prop.Value = "'" + $prop.Value }
        }
    }
    $rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $tempTxt = Join-Path $Root "$hostName.dxdiag-pending.txt"
    if (Test-Path -LiteralPath $tempTxt) { Remove-Item -LiteralPath $tempTxt -Force }
    $p = Start-Process -FilePath "$env:SystemRoot\System32\dxdiag.exe" -ArgumentList "/whql:off /t `"$tempTxt`"" -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(180000)) { throw 'DxDiag did not finish within 3 minutes.' }
    # DxDiag can hand off to another process. Wait for a completed, stable report.
    $deadline = (Get-Date).AddSeconds(90)
    $previousLength = -1
    $stable = 0
    do {
        Start-Sleep -Seconds 3
        $file = Get-Item -LiteralPath $tempTxt -ErrorAction SilentlyContinue
        if ($file -and $file.Length -gt 500 -and $file.Length -eq $previousLength) { $stable++ } else { $stable = 0 }
        if ($file) { $previousLength = $file.Length }
    } until ($stable -ge 3 -or (Get-Date) -gt $deadline)
    if ($stable -lt 3) { throw 'DxDiag report missing or incomplete.' }
    Move-Item -LiteralPath $tempTxt -Destination $txt -Force
    if ((Import-Csv -LiteralPath $csv).Count -lt 1) { throw 'Empty CSV report.' }
    Write-ITLog "SUCCESS: $csv ; $txt. Office subscription licensing may not be exposed by WMI; Unknown is not Unlicensed." 'Inventory.log'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
} catch {
    Write-ITLog "ERROR: $($_.Exception.Message). Task retained for retry." 'Inventory.log'
    exit 1
}

. "$PSScriptRoot\Common.ps1"
$mutex = New-Object Threading.Mutex($false, 'Global\BCMBP-IT-DiskMonitor')
$locked = $false
try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { exit 0 }
    $cfg = Get-Content -LiteralPath "$Root\VolumeInfo.json" -Raw | ConvertFrom-Json
    $c = Get-CimInstance Win32_Volume -Filter "DriveLetter='C:'"
    if (-not $c -or $null -eq $c.FreeSpace) { throw 'Cannot read C: free space.' }
    $cBand = Get-DiskBand $c.FreeSpace
    Write-ITLog "C: FreeGB=$([math]::Round($c.FreeSpace/1GB,2)) Band=$cBand"
    if ($cBand -ne 'Normal') {
        [void](Send-ITMessage "IT-MAINTENANCE: O C: CON $([math]::Round($c.FreeSpace/1GB,2)) GB. VUI LONG DON DEP. HE THONG KHONG AN O C:.")
    }
    if (-not $cfg.MonitorD) { Write-ITLog 'D monitoring disabled: no supported D: at setup.'; exit 0 }
    $d = Get-ManagedVolume $cfg
    $band = Get-DiskBand $d.FreeSpace
    Write-ITLog "D volume: Letter=$($d.DriveLetter) FreeGB=$([math]::Round($d.FreeSpace/1GB,2)) Band=$band"
    if (-not $d.DriveLetter) {
        if ($d.FreeSpace -ge 20GB) {
            Set-ManagedDriveLetter $cfg Assign
            [void](Send-ITMessage 'IT-MAINTENANCE: DA GAN LAI O D:. DUNG LUONG TRONG >=20 GB.')
        }
        exit 0
    }
    if ($d.DriveLetter -ne 'D:') { throw 'Managed volume letter changed; will not modify it.' }
    if ($band -eq 'Warning') {
        [void](Send-ITMessage "IT-MAINTENANCE: O D: CON $([math]::Round($d.FreeSpace/1GB,2)) GB. VUI LONG DON DEP. AN O D: CHI AP DUNG KHI CNTT DA BAT TUY CHON NAY.")
        exit 0
    }
    if ($band -eq 'Critical') {
        if (-not $cfg.HideDWhenCritical) {
            [void](Send-ITMessage "IT-MAINTENANCE: O D: CON $([math]::Round($d.FreeSpace/1GB,2)) GB. VUI LONG DON DEP. TUY CHON AN O D: DANG TAT.")
            exit 0
        }
        $sent = Send-ITMessage "IT-MAINTENANCE: O D: CON $([math]::Round($d.FreeSpace/1GB,2)) GB. BAN CO 60 PHUT DON DEP VA LUU CONG VIEC. NEU VAN DUOI 20 GB, KY TU D: SE BI GO. LIEN HE CNTT DE KHOI PHUC."
        if (-not $sent) { throw 'Warning could not be sent; refusing to remove D: without notification.' }
        Start-Sleep -Seconds 3600
        $d = Get-ManagedVolume $cfg
        if ($d.FreeSpace -ge 20GB) {
            [void](Send-ITMessage 'IT-MAINTENANCE: D: DA TRONG >=20 GB. KHONG GO KY TU O DIA.')
        } elseif ($cfg.HideDWhenCritical) {
            Set-ManagedDriveLetter $cfg Remove
            [void](Send-ITMessage 'IT-MAINTENANCE: DA GO KY TU D: VI VAN DUOI 20 GB. DU LIEU KHONG BI XOA. LIEN HE CNTT DE KHOI PHUC VA DON DEP.')
        }
        exit 0
    }
    if ($cBand -eq 'Normal') {
        $errorsFound = @()
        foreach ($drive in @('C:','D:')) {
            $volume = Get-CimInstance Win32_Volume -Filter "DriveLetter='$drive'"
            if ($volume.FileSystem -ne 'NTFS') { Write-ITLog "$drive not NTFS; skip scan/optimization."; continue }
            # /forceofflinefix queues problems; does not perform online repairs or schedule a reboot.
            $out = & "$env:SystemRoot\System32\chkdsk.exe" $drive /scan /forceofflinefix 2>&1
            $code = $LASTEXITCODE
            Write-ITLog "CHKDSK $drive exit=$code | $($out -join ' | ')"
            if ($code -ne 0) { $errorsFound += $drive; continue }
            $out = & "$env:SystemRoot\System32\defrag.exe" $drive /O 2>&1
            $code = $LASTEXITCODE
            Write-ITLog "OPTIMIZE $drive exit=$code | $($out -join ' | ')"
            if ($code -ne 0) { $errorsFound += $drive }
        }
        if ($errorsFound.Count) {
            [void](Send-ITMessage "IT-MAINTENANCE: MAY $env:COMPUTERNAME CAN CNTT KIEM TRA $($errorsFound -join ', '). XEM NHAT KY. KHONG TU DONG RESTART.")
            exit 1
        }
    }
} catch {
    Write-ITLog "ERROR: $($_.Exception.Message)"
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

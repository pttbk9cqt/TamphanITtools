#requires -Version 5.1
# Run in the normal desktop session of EACH account, not as another administrator.
$ErrorActionPreference = 'Stop'
$networkIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ((New-Object Security.Principal.WindowsPrincipal($networkIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this tool normally in the target desktop account, without Run as administrator.'
}
$file = Join-Path $PSScriptRoot 'O-MANG.json'
Write-Host "Tai khoan hien tai: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
$mode = Read-Host '1 = Sao luu o mang tai khoan nay; 2 = Ket noi o mang vao tai khoan nay'
if ($mode -eq '1') {
    $drives = @{}
    if (Test-Path 'HKCU:\Network') {
        foreach ($key in Get-ChildItem 'HKCU:\Network') {
            $entry = Get-ItemProperty -LiteralPath $key.PSPath
            if ($key.PSChildName -match '^[A-Za-z]$' -and $entry.RemotePath -match '^\\\\[^\\]+\\[^\\]+') {
                $drives[$key.PSChildName.ToUpper()+':'] = [string]$entry.RemotePath
            }
        }
    }
    try {
        foreach ($entry in @(Get-SmbMapping -ErrorAction Stop)) {
            if ($entry.LocalPath -match '^[A-Za-z]:$') { $drives[$entry.LocalPath.ToUpper()] = [string]$entry.RemotePath }
        }
    } catch { Write-Warning "Cannot read live mappings; using saved mappings: $($_.Exception.Message)" }
    if (-not $drives.Count) { throw 'Khong tim thay o mang. Dang nhap tai khoan cu de sao luu, hoac cung cap duong dan UNC cho CNTT.' }
    $rows = @($drives.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{Drive=$_; Path=$drives[$_]} })
    $rows | Format-Table
    if ((Test-Path -LiteralPath $file) -and (Read-Host 'Da co O-MANG.json. Go OVERWRITE de ghi de') -cne 'OVERWRITE') { return }
    ConvertTo-Json -InputObject $rows | Set-Content -LiteralPath $file -Encoding UTF8
    Write-Host "Da luu $file. Chi gom ky tu o va duong dan, khong co mat khau."
} elseif ($mode -eq '2') {
    $rows = @(Get-Content -LiteralPath $file -Raw | ConvertFrom-Json)
    $seen = @{}
    foreach ($row in $rows) {
        if ($row.Drive -notmatch '^[A-Za-z]:$' -or $row.Path -notmatch '^\\\\[^\\]+\\[^\\]+' -or $row.Path -match '[\r\n"]') { throw 'O-MANG.json co duong dan/ky tu o khong hop le.' }
        if ($seen.ContainsKey($row.Drive)) { throw 'Trung ky tu o trong O-MANG.json.' }
        $seen[$row.Drive]=$true
    }
    $rows | Format-Table
    if ((Read-Host 'Go CONNECT de ket noi cac o tren cho tai khoan hien tai') -ine 'CONNECT') { return }
    foreach ($row in $rows) {
        $letter=$row.Drive.Substring(0,1)
        $existing=Get-PSDrive -Name $letter -ErrorAction SilentlyContinue
        $saved=Get-ItemProperty -LiteralPath "HKCU:\Network\$letter" -ErrorAction SilentlyContinue
        if ($existing -or $saved) {
            if (($existing.DisplayRoot -and $existing.DisplayRoot -ine $row.Path) -or ($saved.RemotePath -and $saved.RemotePath -ine $row.Path) -or ($existing -and -not $existing.DisplayRoot -and -not $saved)) {
                Write-Warning "Bo qua $($row.Drive): ky tu o dang duoc dung cho vi tri khac. Khong xoa ket noi hien co."
                continue
            }
            if (Test-Path -LiteralPath ($row.Drive+'\')) { Write-Host "$($row.Drive) da truy cap duoc."; continue }
        }
        & "$env:SystemRoot\System32\net.exe" use $row.Drive $row.Path /persistent:yes
        if ($LASTEXITCODE -ne 0) {
            $networkUser=Read-Host "Nhap tai khoan may chu cho $($row.Path) (DOMAIN\user); Enter de bo qua"
            if ($networkUser) {
                # net.exe prompts for the password without storing it in this script or JSON.
                & "$env:SystemRoot\System32\net.exe" use $row.Drive $row.Path '*' "/user:$networkUser" /persistent:yes
                if ($LASTEXITCODE -ne 0) { Write-Warning "Khong ket noi duoc $($row.Drive). Kiem tra mang, quyen share va thong tin dang nhap." }
            }
        }
    }
} else { Write-Host 'Khong thay doi gi.' }

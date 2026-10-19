function Invoke-WinUtilMaintenanceAccounts {
    <# .SYNOPSIS
        Configures local accounts and computer name using the ComputerMaintenance phase-one workflow.
    #>
    param(
        [string]$NewComputerName,
        [string]$EmployeeFullName,
        [string]$EmployeeUserName,
        [ValidateSet('Users','Power Users')][string]$EmployeeGroup = 'Users',
        [string]$AdminUserName = 'adminbcmbp',
        [string]$AdminFullName,
        [securestring]$EmployeePassword,
        [securestring]$AdminPassword,
        [bool]$ResetAdminPassword = $false,
        [bool]$ResetExistingEmployeePassword = $false,
        [bool]$RequireEmployeePasswordChange = $true,
        [pscredential]$DomainCredential
    )
    $ErrorActionPreference = 'Stop'
    function ConvertTo-EmployeeName([string]$FullName) {
        $normalized = $FullName.Replace('đ','d').Replace('Đ','D').Normalize([Text.NormalizationForm]::FormD)
        $result = New-Object Text.StringBuilder
        foreach ($char in $normalized.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$result.Append($char) }
        }
        return ($result.ToString().ToLowerInvariant() -replace '[^a-z0-9]','')
    }
    try {
        # ----- Preflight: no passwords are printed or written to the installed payloads -----
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open Windows PowerShell with Run as administrator.' }
        if (-not [Environment]::Is64BitProcess -or $PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use 64-bit Windows PowerShell 5.1 (powershell.exe), not PowerShell 7 or x86.' }
        $machine = Get-CimInstance Win32_ComputerSystem
        if ($machine.DomainRole -ge 4) { throw 'Do not run on a domain controller.' }
        if ($env:SystemDrive -ne 'C:') { throw 'This installer requires Windows on C:.' }
        if ($NewComputerName -notmatch '^(?=.{1,15}$)(?![0-9]+$)[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$') { throw 'Invalid computer name: 1-15 letters/digits/hyphens; not all digits.' }
        if ([string]::IsNullOrWhiteSpace($EmployeeFullName)) { throw 'Enter the employee full name.' }
        $EmployeeFullName = $EmployeeFullName.Trim()
        if (-not $EmployeeFullName -or $EmployeeFullName.Length -gt 48) { throw 'Employee full name must be 1-48 characters.' }
        if (-not $EmployeeUserName) { $EmployeeUserName = ConvertTo-EmployeeName $EmployeeFullName }
        if ($EmployeeUserName -notmatch '^[a-z][a-z0-9]{0,19}$') { throw 'Set EmployeeUserName explicitly: 1-20 lowercase ASCII letters/digits, starting with a letter.' }
        if ($EmployeeUserName -eq $AdminUserName) { throw 'Employee and administrator usernames must be different.' }
        if ($EmployeeGroup -notin @('Users','Power Users')) { throw 'EmployeeGroup must be Users or Power Users.' }
        foreach ($cmd in @('Get-LocalUser','Rename-Computer')) { [void](Get-Command $cmd -ErrorAction Stop) }
        $builtIn = @(Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' })
        if ($builtIn.Count -ne 1) { throw 'Cannot uniquely locate the local built-in Administrator by SID.' }
        $builtIn = $builtIn[0]
        $collision = Get-LocalUser -Name $AdminUserName -ErrorAction SilentlyContinue
        if ($collision -and $collision.SID -ne $builtIn.SID) { throw 'adminbcmbp already exists but is NOT the built-in administrator. No account changed.' }
        $employee = Get-LocalUser -Name $EmployeeUserName -ErrorAction SilentlyContinue
        if ($employee -and $employee.SID.Value -match '-(500|501|503|504)$') { throw 'Employee name resolves to a built-in system account.' }
        if ($employee -and $employee.FullName -ne $EmployeeFullName) { throw 'Existing username has a different full name. Resolve the name collision before rerunning.' }
        if ($employee -and $employee.SID -eq $identity.User) { throw 'Do not configure/demote the currently logged-on employee. Run from the IT administrator account.' }

        if ($machine.PartOfDomain -and $env:COMPUTERNAME -ine $NewComputerName) {

            if (-not $domainCredential) { throw 'Domain credential is required to rename this domain computer.' }
        }
        if (($ResetAdminPassword -and (-not $AdminPassword -or $AdminPassword.Length -eq 0)) -or
            ((-not $employee -or $ResetExistingEmployeePassword) -and (-not $EmployeePassword -or $EmployeePassword.Length -eq 0))) {
            throw 'Enter a non-empty password for each account being created or reset.'
        }
        if ($AdminUserName -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,19}$') { throw 'Invalid administrator username.' }
        # ----- Rename: no reboot here -----
        if ($env:COMPUTERNAME -ine $NewComputerName) {
            $rename = @{NewName=$NewComputerName; Force=$true; ErrorAction='Stop'}
            if ($domainCredential) { $rename.DomainCredential = $domainCredential }
            Rename-Computer @rename
        }
        # ----- Accounts -----
        $adminGroup = Get-LocalGroup -SID 'S-1-5-32-544'
        if ($ResetAdminPassword) { Set-LocalUser -SID $builtIn.SID -Password $AdminPassword }
        Set-LocalUser -SID $builtIn.SID -FullName $AdminFullName -PasswordNeverExpires $true

        Enable-LocalUser -SID $builtIn.SID
        if (-not @(Get-LocalGroupMember -Group $adminGroup | Where-Object SID -eq $builtIn.SID).Count) { Add-LocalGroupMember -Group $adminGroup -Member (Get-LocalUser -SID $builtIn.SID) }
        $created = $false
        if (-not $employee) {
            $employee = New-LocalUser -Name $EmployeeUserName -FullName $EmployeeFullName -Password $EmployeePassword -Description 'Tai khoan lam viec nhan vien'
            $created = $true
        } else {
            Set-LocalUser -SID $employee.SID -FullName $EmployeeFullName
            if ($ResetExistingEmployeePassword) { Set-LocalUser -SID $employee.SID -Password $EmployeePassword }
        }
        Set-LocalUser -SID $employee.SID -UserMayChangePassword $true -PasswordNeverExpires $false
        Enable-LocalUser -SID $employee.SID
        # Remove direct privileged memberships, retain only requested standard groups.
        $allowedSids = @('S-1-5-32-545')
        if ($EmployeeGroup -eq 'Power Users') { $allowedSids += 'S-1-5-32-547' }
        foreach ($group in Get-LocalGroup) {
            if ($group.SID.Value -notin $allowedSids) {
                if (@(Get-LocalGroupMember -Group $group -ErrorAction Stop | Where-Object SID -eq $employee.SID).Count) {
                    Remove-LocalGroupMember -Group $group -Member $employee
                }
            }
        }
        foreach ($sid in $allowedSids) {
            $group = Get-LocalGroup -SID $sid
            if (-not @(Get-LocalGroupMember -Group $group | Where-Object SID -eq $employee.SID).Count) { Add-LocalGroupMember -Group $group -Member $employee }
        }
        if ($RequireEmployeePasswordChange -and ($created -or $ResetExistingEmployeePassword)) {
            & "$env:SystemRoot\System32\net.exe" user $EmployeeUserName /logonpasswordchg:yes | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Cannot require employee password change at next logon.' }
        }

        # Rename the active administrator LAST; do not run CIM/DISM after this.
        if ($builtIn.Name -ne $AdminUserName) { Rename-LocalUser -SID $builtIn.SID -NewName $AdminUserName }
        Write-Host 'PHAN 1 HOAN TAT. Luu tai lieu, chon Start > Power > Restart.'
        Write-Host "Sau khi restart, dang nhap .\$EmployeeUserName, doi mat khau neu duoc yeu cau, roi mo Maintenance > Install maintenance."
    } catch {
        Write-Host "PHAN 1 DUNG: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Cac buoc truoc co the da hoan tat. Khong tu dong restart.'
        throw
    } finally {
        $AdminPassword=$null; $EmployeePassword=$null; $domainCredential=$null
    }
}

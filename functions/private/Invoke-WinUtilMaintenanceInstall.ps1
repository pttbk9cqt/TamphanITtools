function Invoke-WinUtilMaintenanceInstall {
    <# .SYNOPSIS
        Installs the embedded ComputerMaintenance scripts and scheduled tasks.
    #>
    param(
        [string]$EmployeeUserName,
        [bool]$HideDWhenCritical = $false,
        [bool]$KeepOneDrive = $true,
        [bool]$EnableNumLock = $true,
        [bool]$RemoveBundledApps = $false,
        [bool]$EnableShutdown = $false
    )
    $AppsToRemove = @(
        'Microsoft.GamingApp','Microsoft.XboxApp','Microsoft.XboxGamingOverlay',
        'Microsoft.XboxGameOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.Xbox.TCUI','Clipchamp.Clipchamp','Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted',
        'Microsoft.WindowsFeedbackHub','Microsoft.WindowsMaps','Microsoft.MixedReality.Portal',
        'Microsoft.Microsoft3DViewer','Microsoft.MSPaint','Microsoft.SkypeApp'
    )
    $ErrorActionPreference = 'Stop'
    $Root = 'C:\IT-MAINTENANCE'
    $warnings = New-Object 'Collections.Generic.List[string]'

    function Warn([string]$Text) { $warnings.Add($Text); Write-WinUtilLog -Component Maintenance -Level WARN -Message $Text }
    function Assert-PlainPath([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $node = Get-Item -LiteralPath $Path -Force
        while ($node) {
            if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point is not allowed: $Path" }
            $node = $node.Parent
        }
    }
    function Protect-InstallFolder {
        Assert-PlainPath $Root
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false)
        $adminSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $acl.SetOwner($adminSid)
        foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
            $rule = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
            [void]$acl.AddAccessRule($rule)
        }
        $rule = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')
        [void]$acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $Root -AclObject $acl
        # Reset children to the protected parent ACL (no writable elevated scripts).
        if (@(Get-ChildItem -LiteralPath $Root -Force).Count) {
            & "$env:SystemRoot\System32\icacls.exe" "$Root\*" /reset /T /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not secure all files in maintenance folder.' }
        }
    }
    function Write-Payload([string]$File,[string]$Base64) {
        $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64))
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$parseErrors)
        if ($parseErrors.Count) { throw "Invalid embedded script: $File" }
        [IO.File]::WriteAllText((Join-Path $Root $File),$text,(New-Object Text.UTF8Encoding($true)))
    }
    function Set-NumLockInHive([string]$Hive) {
        $key = "$Hive\Control Panel\Keyboard"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name InitialKeyboardIndicators -PropertyType String -Value '2' -Force | Out-Null
    }
    function Set-ProfileNumLock([string]$File,[string]$SID) {
        if ($SID -and (Test-Path "Registry::HKEY_USERS\$SID")) { Set-NumLockInHive "Registry::HKEY_USERS\$SID"; return }
        if (-not (Test-Path -LiteralPath $File)) { return }
        $mount = 'ITNumLock_' + [guid]::NewGuid().ToString('N')
        & reg.exe load "HKU\$mount" $File 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Cannot load user hive for NumLock: $File"; return }
        try { Set-NumLockInHive "Registry::HKEY_USERS\$mount" }
        finally {
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
            & reg.exe unload "HKU\$mount" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Warn "Could not unload registry hive $mount" }
        }
    }
    function Register-ITTask([string]$Name,$Action,$Triggers,[string]$Description,[int]$Hours=4) {
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours $Hours)
        Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Triggers -Principal $principal -Settings $settings -Description $Description -Force | Out-Null
    }
    function New-ITScriptAction([string]$File) {
        New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Root\$File`"" -WorkingDirectory $Root
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
        # Use the existing employee explicitly, never the elevated administrator identity.
        $NewComputerName = $env:COMPUTERNAME
        if ([string]::IsNullOrWhiteSpace($EmployeeUserName)) { throw 'Enter the employee login name.' }
        $EmployeeUserName = $EmployeeUserName.Trim()
        $employee = Get-LocalUser -Name $EmployeeUserName -ErrorAction Stop
        if (-not $employee.Enabled -or $employee.SID.Value -match '-(500|501|503|504)$') { throw 'Choose an enabled employee account, not a built-in account.' }
        $EmployeeFullName = $employee.FullName
        $employeeProfile = @(Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $employee.SID.Value -and $_.Loaded })
        if ($employeeProfile.Count -ne 1) { throw 'Sign in as the employee first, then launch phase 2 and approve administrator credentials.' }
        foreach ($cmd in @('Get-Partition','Get-AppxPackage','Register-ScheduledTask')) { [void](Get-Command $cmd -ErrorAction Stop) }
        Assert-PlainPath $Root
        if (Test-Path -LiteralPath $Root) {
            if (@(Get-ChildItem -LiteralPath $Root -Force -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Destination contains junctions/symlinks.' }
        }
        # Preserve D volume identity on repeat runs, including when its letter is absent.
        $volumeConfig = $null
        if (Test-Path -LiteralPath "$Root\VolumeInfo.json") {
            $volumeConfig = Get-Content -LiteralPath "$Root\VolumeInfo.json" -Raw | ConvertFrom-Json
            if (-not ($volumeConfig.PSObject.Properties.Name -contains 'MonitorD')) { $volumeConfig | Add-Member NoteProperty MonitorD $true }
        }
        if (-not $volumeConfig -or -not $volumeConfig.MonitorD) {
            $d = Get-CimInstance Win32_Volume -Filter "DriveLetter='D:'"
            if ($d -and $d.DriveType -eq 3) {
                $part = Get-Partition -DriveLetter D
                $disk = Get-Disk -Number $part.DiskNumber
                if ($part.IsBoot -or $part.IsSystem -or $d.BootVolume -or $d.SystemVolume -or $d.PageFilePresent -or $disk.BusType -eq 'USB') { throw 'D: is boot/system/pagefile/USB. Resolve before enabling letter removal.' }
                $volumeConfig = [pscustomobject]@{ MonitorD=$true; VolumeGUID=$d.DeviceID; DriveLetter='D'; HideDWhenCritical=$HideDWhenCritical }
            } else {
                $volumeConfig = [pscustomobject]@{ MonitorD=$false; VolumeGUID=''; DriveLetter='D'; HideDWhenCritical=$false }
                Warn 'No fixed data volume D:. Only C: monitoring will be installed; rerun after adding D:.'
            }
        }
        $volumeConfig | Add-Member NoteProperty HideDWhenCritical $HideDWhenCritical -Force
        # ----- Copy and protect local scripts -----
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        foreach ($task in @('IT-MAINTENANCE','IT-CLEAN','IT-INVENTORY-ONCE')) {
            if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
                Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
                Disable-ScheduledTask -TaskName $task | Out-Null
            }
        }
        Protect-InstallFolder
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $backup = Join-Path $Root "Backup\$stamp"
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        foreach ($file in @(Get-ChildItem -LiteralPath $Root -File)) { Copy-Item -LiteralPath $file.FullName -Destination $backup -Force }

        Protect-InstallFolder


        Write-Host "Installing for $EmployeeFullName ($EmployeeUserName), computer $NewComputerName"
        Write-Payload 'Common.ps1' $sync.configs.maintenanceScripts.Common
        Write-Payload 'IT-MAINTENANCE.ps1' $sync.configs.maintenanceScripts.DiskMonitor
        Write-Payload 'Cleaner.ps1' $sync.configs.maintenanceScripts.Cleaner
        Write-Payload 'Inventory.ps1' $sync.configs.maintenanceScripts.Inventory
        Write-Payload 'Restore-D.ps1' $sync.configs.maintenanceScripts.RestoreD
        $volumeConfig | ConvertTo-Json | Set-Content -LiteralPath "$Root\VolumeInfo.json" -Encoding UTF8
        # Validate saved identity BEFORE installing a task that can remove a letter.
        . "$Root\Common.ps1"
        if ($volumeConfig.MonitorD) { [void](Get-ManagedPartition $volumeConfig) }
        # ----- Num Lock: WinUtil setting + employee/new-profile coverage -----
        if ($EnableNumLock) {
            Set-NumLockInHive 'Registry::HKEY_USERS\.DEFAULT'
            Set-NumLockInHive 'Registry::HKEY_CURRENT_USER'
            $profileList = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
            $defaultProfile = [Environment]::ExpandEnvironmentVariables($profileList.Default)
            Set-ProfileNumLock (Join-Path $defaultProfile 'NTUSER.DAT') ''
            foreach ($userProfile in @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath })) {
                Set-ProfileNumLock (Join-Path $userProfile.LocalPath 'NTUSER.DAT') $userProfile.SID
            }
        }
        # ----- Selected built-in applications, all users and future profiles -----
        if ($RemoveBundledApps) {
            $provisionedPackages = @()
            try { $provisionedPackages = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) }
            catch { Warn "Cannot list provisioned apps; skipping removal for future profiles. Setup will continue. Details: $($_.Exception.Message)" }
            foreach ($name in $AppsToRemove) {
                $installedPackages = @()
                try { $installedPackages = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop) }
                catch { Warn "Cannot list installed app $name : $($_.Exception.Message)" }
                foreach ($pkg in $installedPackages) {
                    try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop }
                    catch { Warn "Cannot remove $name : $($_.Exception.Message)" }
                }
                foreach ($pkg in @($provisionedPackages | Where-Object DisplayName -eq $name)) {
                    try { Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null }
                    catch { Warn "Cannot deprovision $name : $($_.Exception.Message)" }
                }
            }
        }
        # ----- OneDrive: WinUtil's native OneDriveSetup.exe /uninstall approach -----
        # Deliberately do NOT replay WinUtil's broad cleanup, ACL edits, Explorer kill,
        # or OneSyncSvc disable (also used by unrelated Windows synchronization).
        if (-not $KeepOneDrive) {
            $profiles = @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath })
            $oneDriveFolders = @()
            foreach ($userProfile in $profiles) {
                $oneDriveFolders += @(Get-ChildItem -LiteralPath $userProfile.LocalPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object Name -like 'OneDrive*' | Select-Object -ExpandProperty FullName)
            }
            if ($oneDriveFolders.Count) { Warn 'OneDrive data folders exist. Files/folder redirection are preserved; cloud-only files require download from OneDrive web after uninstall.' }
            Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
            $candidates = @("$env:SystemRoot\System32\OneDriveSetup.exe","$env:SystemRoot\SysWOW64\OneDriveSetup.exe")
            foreach ($base in @("$env:ProgramFiles\Microsoft OneDrive", "${env:ProgramFiles(x86)}\Microsoft OneDrive", "$env:LOCALAPPDATA\Microsoft\OneDrive")) {
                if ($base -and (Test-Path -LiteralPath $base)) {
                    $candidates += @(Get-ChildItem -LiteralPath $base -Filter OneDriveSetup.exe -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty FullName)
                }
            }
            $ranUninstaller = $false
            foreach ($candidate in @($candidates | Select-Object -Unique)) {
                if (-not (Test-Path -LiteralPath $candidate)) { continue }
                $sig = Get-AuthenticodeSignature -LiteralPath $candidate
                if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { Warn "Skipping untrusted uninstaller: $candidate"; continue }
                $uninstallArguments = '/uninstall'
                if ($candidate.StartsWith($env:ProgramFiles,[StringComparison]::OrdinalIgnoreCase) -or (${env:ProgramFiles(x86)} -and $candidate.StartsWith(${env:ProgramFiles(x86)},[StringComparison]::OrdinalIgnoreCase))) { $uninstallArguments += ' /allusers' }
                $p = Start-Process -FilePath $candidate -ArgumentList $uninstallArguments -Wait -PassThru -WindowStyle Hidden
                if ($p.ExitCode -in @(0,3010)) { $ranUninstaller = $true } else { Warn "OneDrive uninstaller exit=$($p.ExitCode): $candidate" }
            }
            $remaining = @()
            foreach ($userProfile in $profiles) {
                if (Test-Path -LiteralPath (Join-Path $userProfile.LocalPath 'AppData\Local\Microsoft\OneDrive\OneDrive.exe')) { $remaining += $userProfile.LocalPath }
            }
            foreach ($base in @("$env:ProgramFiles\Microsoft OneDrive", "${env:ProgramFiles(x86)}\Microsoft OneDrive")) {
                if (Test-Path -LiteralPath (Join-Path $base 'OneDrive.exe')) { $remaining += $base }
            }
            if ($remaining.Count) { Warn "OneDrive removal INCOMPLETE in: $($remaining -join '; '). Per-user installations under another account need uninstall in that user's context." }
            elseif (-not $ranUninstaller) { Write-Host 'No installed OneDrive/uninstaller found.' }
        }
        # Daily cleanup and shutdown, matching ComputerMaintenance's schedules.
        Register-ITTask -Name 'IT-CLEAN' -Action (New-ITScriptAction 'Cleaner.ps1') -Triggers (New-ScheduledTaskTrigger -Daily -At '12:30') -Description 'Clean temporary files older than 7 days.' -Hours 2
        $shutdownAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\shutdown.exe" -Argument '-s -t 600'
        $shutdownSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $shutdownPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        if ($EnableShutdown) {
            Register-ScheduledTask -TaskName 'IT-SHUTDOWN' -Action $shutdownAction -Trigger (New-ScheduledTaskTrigger -Daily -At '21:30') -Principal $shutdownPrincipal -Settings $shutdownSettings -Description 'Shutdown at 21:40 after a ten-minute countdown starting at 21:30.' -Force | Out-Null
        }
        $triggers = @(
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At '09:00'
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At '14:00'
        )
        Register-ITTask -Name 'IT-MAINTENANCE' -Action (New-ITScriptAction 'IT-MAINTENANCE.ps1') -Triggers $triggers -Description 'C/D monitor; 60 min grace; volume GUID validation; scan and optimize if both >30 GB.' -Hours 12
        # Inventory runs only after a later boot and unregisters itself on success.
        [pscustomobject]@{
            ExpectedComputerName=$NewComputerName
            EmployeeUserName=$EmployeeUserName
            SetupBootUtc=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath "$Root\SetupState.json" -Encoding UTF8
        $startup = New-ScheduledTaskTrigger -AtStartup
        $startup.Delay = 'PT2M'
        Register-ITTask -Name 'IT-INVENTORY-ONCE' -Action (New-ITScriptAction 'Inventory.ps1') -Triggers $startup -Description 'Export software/license and DxDiag report after final restart; self-remove on success.' -Hours 1
        $retry = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -ExecutionTimeLimit (New-TimeSpan -Hours 1)
        Set-ScheduledTask -TaskName 'IT-INVENTORY-ONCE' -Settings $retry | Out-Null
        Protect-InstallFolder
        foreach ($name in @('IT-CLEAN','IT-MAINTENANCE','IT-INVENTORY-ONCE')) {
            Enable-ScheduledTask -TaskName $name | Out-Null
            $task = Get-ScheduledTask -TaskName $name
            if ($task.State -eq 'Disabled') { throw "Task remained disabled: $name" }
        }
        $warnings | Set-Content -LiteralPath "$Root\Setup-Warnings.txt" -Encoding UTF8
        Write-Host "SETUP FINISHED. Warnings: $($warnings.Count). Read C:\IT-MAINTENANCE\Setup-Warnings.txt"
        Write-Host "Employee: .\$EmployeeUserName"
        Write-Host "After restart: C:\IT-MAINTENANCE\$NewComputerName.csv and .txt (allow several minutes)."
        Write-Host 'Save documents before restarting. No separate logout is needed.'
    } catch {
        Write-Host "SETUP STOPPED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'No automatic restart. Earlier steps may already have completed; inspect the setup log, fix the error, then rerun.'
        throw
    }
}

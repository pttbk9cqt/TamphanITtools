function Install-WinUtilOriginalMaintenanceFiles {
    <# .SYNOPSIS
        Deploys the original IT-MAINTENANCE workflow files from compiled payloads.
    #>
    param([string]$Destination = 'C:\IT-MAINTENANCE')

    $ErrorActionPreference = 'Stop'
    $files = @{}
    foreach ($name in @('CLEANER.bat','Task Scheduler.bat','GET-INFOMATION.txt','IT-MAINTENANCE.txt')) {
        $payload = $sync.configs.maintenanceOriginalFiles.$name
        if ([string]::IsNullOrWhiteSpace($payload)) { throw "Missing embedded maintenance file: $name" }
        $files[$name] = [Convert]::FromBase64String($payload)
    }
    $runner = $sync.configs.maintenanceScripts.RunOriginal
    if ([string]::IsNullOrWhiteSpace($runner)) { throw 'Missing embedded maintenance runner.' }
    $runnerText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($runner))
    $files['RunOriginal.ps1'] = (New-Object Text.UTF8Encoding($true)).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($runnerText)

    $node = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if (-not $node) { $node = Get-Item -LiteralPath (Split-Path -Parent $Destination) -Force }
    while ($node) {
        if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Maintenance destination must not contain junctions or symbolic links.' }
        $node = $node.Parent
    }
    if (Test-Path -LiteralPath $Destination) {
        if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { throw 'Maintenance destination is not a folder.' }
        if (@(Get-ChildItem -LiteralPath $Destination -Force -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
            throw 'Maintenance destination contains junctions or symbolic links.'
        }
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        [void]$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    }
    [void]$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))
    Set-Acl -LiteralPath $Destination -AclObject $acl
    if (@(Get-ChildItem -LiteralPath $Destination -Force).Count) {
        & "$env:SystemRoot\System32\icacls.exe" "$Destination\*" /reset /T /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not secure existing maintenance files.' }
    }

    $backup = Join-Path $Destination ('Backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    foreach ($name in $files.Keys) {
        $path = Join-Path $Destination $name
        if (Test-Path -LiteralPath $path) {
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            Copy-Item -LiteralPath $path -Destination $backup -Force
        }
        [IO.File]::WriteAllBytes($path, $files[$name])
    }
    # Inherit the protected parent ACL for both new and previously copied files.
    & "$env:SystemRoot\System32\icacls.exe" "$Destination\*" /reset /T /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not secure all maintenance files.' }
    Write-WinUtilLog -Component Maintenance -Message "Original maintenance files prepared in $Destination. Existing files backed up in $backup when replaced."
}

function Repair-WinUtilWindowsUpdate {
    <# .SYNOPSIS
        Resets update caches without deleting them or changing boot settings.
    #>
    $ErrorActionPreference = 'Stop'
    $windows = [IO.Path]::GetFullPath($env:SystemRoot)
    $paths = @((Join-Path $windows 'SoftwareDistribution'), (Join-Path $windows 'System32\catroot2'))
    # Refuse redirected cache directories rather than touching another target.
    foreach ($path in @($windows, (Join-Path $windows 'System32')) + $paths) {
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Unsafe cache directory: $path. No cache changes were made."
            }
        }
    }
    if (-not (Get-WinUtilWindowsUpdateStatus)) {
        Write-WinUtilLog -Component Updates -Message 'Repair: restoring disabled Windows Update defaults with user consent.'
        Invoke-WPFUpdatesdefault | Out-Null
    }
    $services = @(foreach ($name in 'bits','wuauserv','cryptsvc') { Get-Service -Name $name -ErrorAction Stop })
    $running = @($services | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.Name })
    $backups = [System.Collections.Generic.List[object]]::new()
    $failure = $null
    $restartErrors = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($service in $services) {
            Write-WinUtilLog -Component Updates -Message "Repair: stopping $($service.Name), timeout 20 seconds."
            $service.Refresh()
            if ($service.Status -notin @('Stopped','StopPending')) { $service.Stop() }
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(20))
        }
        $suffix = '.winutil-backup-' + [guid]::NewGuid().ToString('N')
        foreach ($path in $paths) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $backup = $path + $suffix
            Rename-Item -LiteralPath $path -NewName ([IO.Path]::GetFileName($backup)) -ErrorAction Stop
            $backups.Add([pscustomobject]@{ Original = $path; Backup = $backup })
            Write-WinUtilLog -Component Updates -Message "Repair: cache retained at $backup"
        }
    } catch {
        $failure = $_.Exception.Message
        # If only part of the reset completed, restore renamed caches before
        # restarting services. Never overwrite a newly created cache directory.
        foreach ($entry in $backups) {
            try {
                if (-not (Test-Path -LiteralPath $entry.Original)) {
                    Rename-Item -LiteralPath $entry.Backup -NewName ([IO.Path]::GetFileName($entry.Original)) -ErrorAction Stop
                    Write-WinUtilLog -Component Updates -Message "Repair: restored $($entry.Original) after failure."
                }
            } catch {
                $failure += " Rollback failed: $($_.Exception.Message). Backup: $($entry.Backup)."
            }
        }
    } finally {
        foreach ($service in $services) {
            if ($failure -and $running -notcontains $service.Name) { continue }
            try {
                $service.Refresh()
                if ($service.Status -notin @('Running','StartPending')) { $service.Start() }
                $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(20))
                Write-WinUtilLog -Component Updates -Message "Repair: $($service.Name) running."
            } catch {
                $restartErrors.Add("$($service.Name): $($_.Exception.Message)")
            }
        }
    }
    if ($failure -or $restartErrors.Count) {
        throw "Cache repair did not finish: $failure $($restartErrors -join '; '). Any retained backups: $($backups.Backup -join ', ')."
    }
    return "Windows Update cache reset completed. This does not guarantee every update error is fixed. Open Windows Update Settings and check again. No restart was performed.`nCache backups (not deleted): $($backups.Backup -join ', ')"
}

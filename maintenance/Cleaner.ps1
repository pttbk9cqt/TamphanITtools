. "$PSScriptRoot\Common.ps1"
$cutoff = (Get-Date).AddDays(-7)
$count = 0
$skipped = 0
function Remove-OldTempFiles {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    # Validate every ancestor, not just the leaf: never follow junctions/symlinks.
    $node = Get-Item -LiteralPath $resolved -Force
    while ($node) {
        if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
        $node = $node.Parent
    }
    $queue = New-Object 'Collections.Generic.Queue[string]'
    $queue.Enqueue($resolved)
    while ($queue.Count) {
        $dir = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $full = [IO.Path]::GetFullPath($item.FullName)
            if (-not $full.StartsWith($resolved + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup path escaped allowed folder.' }
            if ($item.PSIsContainer) { $queue.Enqueue($full); continue }
            if ($item.LastWriteTime -lt $cutoff) {
                try { Remove-Item -LiteralPath $full -Force -ErrorAction Stop; $script:count++ }
                catch { $script:skipped++ }
            }
        }
    }
}
try {
    Remove-OldTempFiles "$env:SystemRoot\Temp"
    foreach ($userProfile in @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath })) {
        Remove-OldTempFiles (Join-Path $userProfile.LocalPath 'AppData\Local\Temp')
    }
    Write-ITLog "Clean complete: removed=$count locked/skipped=$skipped; files older than 7 days only." 'Cleaner.log'
} catch { Write-ITLog "ERROR: $($_.Exception.Message)" 'Cleaner.log'; exit 1 }

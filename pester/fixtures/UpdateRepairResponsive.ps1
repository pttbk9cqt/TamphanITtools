$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Join-Path $PSScriptRoot '../..')
Add-Type -AssemblyName PresentationFramework
Add-Type @'
using System;
using System.Threading;
public static class RepairUIWatchdog {
    public static Timer Timer;
    public static void Start() { Timer = new Timer(_ => Environment.Exit(99), null, 20000, Timeout.Infinite); }
}
'@
[RepairUIWatchdog]::Start()
. ./functions/public/Invoke-WPFRepairWindowsUpdate.ps1
. ./functions/public/Invoke-WPFRunspace.ps1
. ./functions/private/Initialize-WinUtilRunspacePool.ps1
. ./functions/private/Close-WinUtilRunspacePool.ps1
$sync = [hashtable]::Synchronized(@{
    ProcessRunning = $false; WindowsUpdateRunning = $false; Ticks = 0; Queries = 0; Repairs = 0; FailRepair = $false; Dialogs = 0
    UIThread = [Threading.Thread]::CurrentThread.ManagedThreadId
    Form = [Windows.Window]::new()
    WPFToggleWindowsUpdate = [Windows.Controls.CheckBox]::new()
    WPFToggleMaintenanceWindowsUpdate = [Windows.Controls.CheckBox]::new()
    WPFRepairWindowsUpdate = [Windows.Controls.Button]::new()
})
$PARAM_OFFLINE = $false
# Harmless fixtures replace every system-changing operation.
function Repair-WinUtilWindowsUpdate {
    if ([Threading.Thread]::CurrentThread.ManagedThreadId -eq $sync.UIThread) { throw 'Repair ran on UI thread' }
    Start-Sleep -Milliseconds 200
    $sync.Repairs++
    if ($sync.FailRepair) { throw 'Simulated repair failure' }
    'Simulated cache repair completed.'
}
function Get-WinUtilWindowsUpdateStatus {
    if ([Threading.Thread]::CurrentThread.ManagedThreadId -eq $sync.UIThread) { throw 'Service query ran on UI thread' }
    Start-Sleep -Milliseconds 100
    $sync.Queries++
    $true
}
function Write-WinUtilLog { param($Message,$Level,$Component) }
function Show-WinUtilMessage {
    param($Message,$Title,$Button,$Icon)
    if ([Threading.Thread]::CurrentThread.ManagedThreadId -ne $sync.UIThread) { throw 'Dialog ran off UI thread' }
    $sync.Dialogs++
    'Yes'
}
function Set-WinUtilTweaksProgressIndicator {
    param($Visible,$Label,$Percent)
    if ([Threading.Thread]::CurrentThread.ManagedThreadId -ne $sync.UIThread) { throw 'Progress ran off UI thread' }
}
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(20)
$timer.Add_Tick({
    $sync.Ticks++
    if (-not $sync.ProcessRunning) { $sync.Frame.Continue = $false }
})
try {
    Initialize-WinUtilRunspacePool | Out-Null
    $timer.Start()
    foreach ($fail in @($false,$true)) {
        $sync.FailRepair = $fail
        $before = $sync.Ticks
        $sync.Frame = [Windows.Threading.DispatcherFrame]::new()
        Invoke-WPFRepairWindowsUpdate
        [Windows.Threading.Dispatcher]::PushFrame($sync.Frame)
        if ($sync.Ticks -le $before) { throw 'Dispatcher heartbeat stopped' }
        if ($sync.WindowsUpdateRunning -or -not $sync.WPFRepairWindowsUpdate.IsEnabled) { throw 'Busy state not released' }
        if (-not $sync.WPFToggleWindowsUpdate.IsChecked -or -not $sync.WPFToggleMaintenanceWindowsUpdate.IsChecked) { throw 'Switches not synchronized' }
    }
    if ($sync.Repairs -ne 2 -or $sync.Queries -ne 2 -or $sync.Dialogs -ne 4) { throw 'Unexpected callback counts' }
    'PASS: cache repair kept real WPF responsive on success and failure; no system changes.'
} finally {
    $timer.Stop()
    Close-WinUtilRunspacePool
    $sync.Form.Close()
    [RepairUIWatchdog]::Timer.Dispose()
}

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Join-Path $PSScriptRoot '../..')
Add-Type -AssemblyName PresentationFramework
Add-Type @'
using System;
using System.Threading;
public static class UpdateUIWatchdog {
    public static Timer Timer;
    public static void Start() { Timer = new Timer(_ => Environment.Exit(99), null, 20000, Timeout.Infinite); }
}
'@
[UpdateUIWatchdog]::Start()
. ./functions/public/Invoke-WPFWindowsUpdate.ps1
. ./functions/public/Invoke-WPFRunspace.ps1
. ./functions/private/Initialize-WinUtilRunspacePool.ps1
. ./functions/private/Close-WinUtilRunspacePool.ps1
$sync = [hashtable]::Synchronized(@{
    ProcessRunning = $false
    FixtureEnabled = $true
    QueryCount = 0
    ApplyCount = 0
    Ticks = 0
    Errors = 0
    UIThread = [Threading.Thread]::CurrentThread.ManagedThreadId
    Form = [Windows.Window]::new()
    WPFToggleWindowsUpdate = [Windows.Controls.CheckBox]::new()
    WPFToggleMaintenanceWindowsUpdate = [Windows.Controls.CheckBox]::new()
})
$sync.WPFToggleWindowsUpdate.IsChecked = $true
$sync.WPFToggleWindowsUpdate.Tag = $true
$PARAM_OFFLINE = $false
function Invoke-WPFUpdatesdefault { Start-Sleep -Milliseconds 150; $sync.FixtureEnabled = $true; $sync.ApplyCount++ }
function Invoke-WPFUpdatesdisable { param([switch]$SkipConfirmation) Start-Sleep -Milliseconds 150; $sync.FixtureEnabled = $false; $sync.ApplyCount++ }
function Get-WinUtilWindowsUpdateStatus {
    if ([Threading.Thread]::CurrentThread.ManagedThreadId -eq $sync.UIThread) { throw 'Service query ran on UI thread' }
    Start-Sleep -Milliseconds 150
    $sync.QueryCount++
    $sync.FixtureEnabled
}
function Write-WinUtilLog { param($Message,$Level,$Component) if ($Level -eq 'ERROR') { $sync.Errors++ } }
function Show-WinUtilMessage { param($Message,$Title,$Button,$Icon) if ($Icon -eq 'Error') { throw $Message }; 'Yes' }
function Set-WinUtilTweaksProgressIndicator {
    param($Visible,$Label,$Percent)
    if ([Threading.Thread]::CurrentThread.ManagedThreadId -ne $sync.UIThread) { throw 'Progress update ran off UI thread' }
}
function Invoke-WPFUIThread { param($ScriptBlock) throw 'Synchronous dispatch was used' }
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(20)
$timer.Add_Tick({
    $sync.Ticks++
    if (-not $sync.ProcessRunning) { $sync.Frame.Continue = $false }
})
try {
    Initialize-WinUtilRunspacePool | Out-Null
    $timer.Start()
    foreach ($phase in @('Refresh','Off','On','Off','On')) {
        $beforeTicks = $sync.Ticks
        $sync.Frame = [Windows.Threading.DispatcherFrame]::new()
        if ($phase -eq 'Refresh') { Invoke-WPFWindowsUpdate -Refresh }
        else {
            $controlName = if ($phase -eq 'On') { 'WPFToggleMaintenanceWindowsUpdate' } else { 'WPFToggleWindowsUpdate' }
            $sync[$controlName].IsChecked = ($phase -eq 'On')
            Invoke-WPFWindowsUpdate -Name $controlName
        }
        [Windows.Threading.Dispatcher]::PushFrame($sync.Frame)
        if ($sync.Ticks -le $beforeTicks) { throw 'Dispatcher heartbeat stopped' }
        if (-not $sync.WPFToggleWindowsUpdate.IsEnabled) { throw 'Switch was not restored' }
        if ($sync.WPFToggleWindowsUpdate.IsChecked -ne $sync.FixtureEnabled) { throw 'Switch state mismatch' }
        if ($sync.WPFToggleMaintenanceWindowsUpdate.IsChecked -ne $sync.FixtureEnabled) { throw 'Twin switch state mismatch' }
        Write-Output "$phase completed; dispatcher ticks: $($sync.Ticks - $beforeTicks)"
    }
    if ($sync.QueryCount -ne 5 -or $sync.ApplyCount -ne 4 -or $sync.Errors -ne 0) { throw 'Unexpected worker results' }
    Write-Output 'PASS: real WPF dispatcher and real runspaces remained responsive; no system updates were changed.'
} finally {
    $timer.Stop()
    Close-WinUtilRunspacePool
    $sync.Form.Close()
    [UpdateUIWatchdog]::Timer.Dispose()
}

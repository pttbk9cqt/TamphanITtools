function Initialize-WinUtilTabContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabName
    )

    if ($null -eq $sync.InitializedTabs) {
        $sync.InitializedTabs = @{}
    }

    if ($sync.InitializedTabs[$TabName]) {
        return
    }

    switch ($TabName) {
        "Install" {
            Initialize-WPFUI -targetGridName "appscategory"

            Initialize-WPFUI -targetGridName "appspanel"
        }
        "Tweaks" {
            Invoke-WPFUIElements -configVariable $sync.configs.tweaks -targetGridName "tweakspanel" -columncount 2
        }
        "Maintenance" {
            Invoke-WPFUIElements -configVariable $sync.configs.maintenance -targetGridName "maintenancepanel" -columncount 2
            foreach ($toggleName in @('WPFToggleMaintenanceTasks','WPFToggleMaintenanceMonitor','WPFToggleWindowsUpdate')) {
                Invoke-WPFMaintenanceToggle -Name $toggleName -Refresh
            }
        }
        "AppX" {
            Invoke-WPFUIElements -configVariable $sync.configs.appx -targetGridName "appxpanel" -columncount 2
        }
    }

    $sync.InitializedTabs[$TabName] = $true

    # Sync freshly built controls to any selections already in $sync.selected* (import/preset).
    Reset-WPFCheckBoxes -doToggles $true
}

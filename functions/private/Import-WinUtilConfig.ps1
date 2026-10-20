function Import-WinUtilConfig {
    <# .SYNOPSIS
        Imports application, tweak and AppX selections from the command-line Config path or URL.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Config
    )

    try {
        try {
            if ($Config -match '^https?://') {
                $jsonFile = (Invoke-WebRequest $Config).Content | ConvertFrom-Json
            } else {
                $jsonFile = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
            }
        } catch {
            Write-Error "Failed to load the JSON file from the specified path or URL: $_"
            return
        }

        $isLegacyConfig = $jsonFile -is [System.Management.Automation.PSCustomObject] -and
            $null -ne $jsonFile.PSObject.Properties['Install'] -and
            $null -ne $jsonFile.PSObject.Properties['WPFInstall']
        if ($isLegacyConfig) {
            Write-WinUtilLog -Component Impex -Message 'Detected legacy WinUtil config structure; flattening import object.'
            # Keep retired Feature groups here so legacy imports report them as skipped.
            $flattenedJson = @(
                foreach ($property in $jsonFile.PSObject.Properties) {
                    if ($property.Name -notmatch '^WPF(?:Install|Tweaks|Toggle|Feature|Appx)') { continue }
                    foreach ($selection in @($property.Value)) {
                        if ($selection -is [string] -and -not [string]::IsNullOrWhiteSpace($selection)) { $selection }
                    }
                }
            )
        } else {
            $flattenedJson = $jsonFile
        }

        if (-not $flattenedJson) {
            Write-Warning 'The selected file contains no settings to import. No changes have been made.'
            return
        }

        if ($isLegacyConfig) {
            $skippedSelections = @(Update-WinUtilSelections -flatJson $flattenedJson -Replace -SkipUnknown)
            if ($skippedSelections.Count -gt 0) {
                Write-WinUtilLog -Component Impex -Level WARN -Message "Skipped unsupported legacy selections: $($skippedSelections -join ', ')"
            }
            if ($skippedSelections.Count -eq @($flattenedJson).Count) {
                if ($sync.Form) {
                    Show-WinUtilMessage -Message 'This legacy configuration contains no settings supported by this version of WinUtil. No changes have been made.' -Title 'Unsupported Legacy Configuration' -Icon Warning | Out-Null
                }
                return
            }
            if ($skippedSelections.Count -gt 0 -and $sync.Form) {
                $skippedDisplay = @($skippedSelections | Select-Object -First 10) -join ', '
                if ($skippedSelections.Count -gt 10) {
                    $skippedDisplay += "`n...and $($skippedSelections.Count - 10) more. See the WinUtil log for details."
                }
                Show-WinUtilMessage -Message "Supported settings were imported. The following retired settings were skipped:`n`n$skippedDisplay" -Title 'Legacy Configuration Partially Imported' -Icon Warning | Out-Null
            }
        } else {
            Update-WinUtilSelections -flatJson $flattenedJson -Replace
        }
        if ($sync.Form) { Reset-WPFCheckBoxes -doToggles $true }
    } catch {
        Write-Error "An error occurred while importing: $_"
    }
}

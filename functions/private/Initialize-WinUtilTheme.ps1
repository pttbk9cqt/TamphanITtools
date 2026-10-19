function Initialize-WinUtilTheme {
    <#
    .SYNOPSIS
        Loads the fixed Light visual resources required by the WinUtil WPF window.
    #>
    function Set-WinUtilThemeResource {
        param($Name, $Value, $Type)

        $sync.Form.Resources[$Name] = switch ($Type) {
            "ColorBrush" { [Windows.Media.SolidColorBrush]::new($Value) }
            "Color" {
                $hexColor = $Value.TrimStart("#")
                [Windows.Media.Color]::FromRgb(
                    [Convert]::ToInt32($hexColor.Substring(0, 2), 16),
                    [Convert]::ToInt32($hexColor.Substring(2, 2), 16),
                    [Convert]::ToInt32($hexColor.Substring(4, 2), 16)
                )
            }
            "CornerRadius" { [System.Windows.CornerRadius]::new($Value) }
            "GridLength" { [System.Windows.GridLength]::new($Value) }
            "Thickness" {
                $values = $Value -split ","
                switch ($values.Count) {
                    1 { [System.Windows.Thickness]::new([double]$values[0]) }
                    2 { [System.Windows.Thickness]::new([double]$values[0], [double]$values[1]) }
                    4 { [System.Windows.Thickness]::new([double]$values[0], [double]$values[1], [double]$values[2], [double]$values[3]) }
                }
            }
            "FontFamily" { [Windows.Media.FontFamily]::new($Value) }
            default { [double]$Value }
        }
    }

    foreach ($themeName in @("shared", "Light")) {
        foreach ($property in $sync.configs.themes.$themeName.PSObject.Properties) {
            $type = if ($property.Name -like "*color*") {
                "ColorBrush"
            }
            elseif ($property.Name -like "*Radius*") {
                "CornerRadius"
            }
            elseif ($property.Name -like "*RowHeight*") {
                "GridLength"
            }
            elseif (($property.Name -like "*Thickness*") -or ($property.Name -like "*margin")) {
                "Thickness"
            }
            elseif ($property.Name -like "*FontFamily*") {
                "FontFamily"
            }
            else {
                "Double"
            }

            Set-WinUtilThemeResource -Name $property.Name -Value $property.Value -Type $type
            if ($property.Name -in @("BorderColor", "ButtonBackgroundMouseoverColor")) {
                Set-WinUtilThemeResource -Name "C$($property.Name)" -Value $property.Value -Type "Color"
            }
        }
    }
}

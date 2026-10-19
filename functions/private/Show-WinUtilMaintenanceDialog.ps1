function Show-WinUtilMaintenanceDialog {
    <# .SYNOPSIS
        Collects maintenance settings without storing passwords in files or shared UI state.
    #>
    param([ValidateSet('Accounts','Install')][string]$Action)

    $window = New-Object Windows.Window
    $window.Title = "Maintenance - $Action"
    $window.Owner = $sync.Form
    $window.WindowStartupLocation = 'CenterOwner'
    $window.Width = 560
    $window.Height = 650
    $window.ResizeMode = 'CanResize'
    $window.Background = $sync.Form.FindResource('MainBackgroundColor')
    $window.Foreground = $sync.Form.FindResource('MainForegroundColor')
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = 20
    $scroll = New-Object Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.Content = $panel
    $window.Content = $scroll
    $fields = @{}

    $description = New-Object Windows.Controls.TextBlock
    $description.TextWrapping = 'Wrap'
    $description.Margin = '0,0,0,12'
    $description.Text = if ($Action -eq 'Accounts') {
        'Run from an IT administrator account. Existing employee memberships will be restricted to Users (and optionally Power Users). Save work and restart manually after completion.'
    } else {
        'Sign in as the employee first, then elevate WinUtil. Installs scripts to C:\IT-MAINTENANCE, daily cleanup at 12:30, weekday disk checks at 09:00 and 14:00, and reports after the next restart. Optional changes are listed below.'
    }
    [void]$panel.Children.Add($description)

    if ($Action -eq 'Accounts') {
        $textFields = @(
            @('NewComputerName', 'Computer name (1-15 characters)', $env:COMPUTERNAME),
            @('EmployeeFullName', 'Employee full name', ''),
            @('EmployeeUserName', 'Employee login (blank = derive from full name)', ''),
            @('AdminUserName', 'Built-in Administrator new login', 'adminbcmbp'),
            @('AdminFullName', 'Administrator display name', 'IT Administrator')
        )
    } else {
        $textFields = @(, @('EmployeeUserName', 'Existing employee login (loaded profile required)', ''))
    }
    foreach ($field in $textFields) {
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = $field[1]
        $label.Margin = '0,6,0,3'
        [void]$panel.Children.Add($label)
        $box = New-Object Windows.Controls.TextBox
        $box.Text = $field[2]
        $box.Padding = 4
        [void]$panel.Children.Add($box)
        $fields[$field[0]] = $box
    }

    if ($Action -eq 'Accounts') {
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = 'Employee group'
        $label.Margin = '0,6,0,3'
        [void]$panel.Children.Add($label)
        $group = New-Object Windows.Controls.ComboBox
        [void]$group.Items.Add('Users')
        [void]$group.Items.Add('Power Users')
        $group.SelectedIndex = 0
        [void]$panel.Children.Add($group)
        $fields.EmployeeGroup = $group
        foreach ($entry in @(@('EmployeePassword','Employee password (required for a new account or reset)'), @('AdminPassword','Administrator password (only used if reset is checked)'))) {
            $label = New-Object Windows.Controls.TextBlock
            $label.Text = $entry[1]
            $label.Margin = '0,6,0,3'
            [void]$panel.Children.Add($label)
            $password = New-Object Windows.Controls.PasswordBox
            $password.Padding = 4
            [void]$panel.Children.Add($password)
            $fields[$entry[0]] = $password
        }
    }

    $checks = if ($Action -eq 'Accounts') {
        @(
            @('ResetAdminPassword','Reset the existing administrator password', $false),
            @('ResetExistingEmployeePassword','Reset the existing employee password', $false),
            @('RequireEmployeePasswordChange','Require employee password change after creation/reset', $true)
        )
    } else {
        @(
            @('EnableNumLock','Enable Num Lock for existing and new profiles', $true),
            @('HideDWhenCritical','Allow removing D: after warning + 60 min below 20 GB', $false),
            @('EnableShutdown','Schedule daily shutdown at 21:30 (10 minute countdown)', $false),
            @('RemoveBundledApps','Remove the bundled app list for all users and future profiles', $false),
            @('KeepOneDrive','Keep OneDrive installed', $true)
        )
    }
    foreach ($entry in $checks) {
        $check = New-Object Windows.Controls.CheckBox
        $check.Content = $entry[1]
        $check.IsChecked = $entry[2]
        $check.Margin = '0,10,0,0'
        [void]$panel.Children.Add($check)
        $fields[$entry[0]] = $check
    }
    $submit = New-Object Windows.Controls.Button
    $submit.Content = 'Review and continue'
    $submit.Margin = '0,18,0,0'
    $submit.Padding = 8
    $submit.Add_Click({ $window.DialogResult = $true })
    [void]$panel.Children.Add($submit)
    try {
        if ($window.ShowDialog() -ne $true) { return }
        $options = @{}
        foreach ($key in $fields.Keys) {
            $control = $fields[$key]
            if ($control -is [Windows.Controls.PasswordBox]) { $options[$key] = $control.SecurePassword.Copy() }
            elseif ($control -is [Windows.Controls.CheckBox]) { $options[$key] = [bool]$control.IsChecked }
            elseif ($control -is [Windows.Controls.ComboBox]) { $options[$key] = [string]$control.SelectedItem }
            else { $options[$key] = $control.Text.Trim() }
        }
        return $options
    } finally {
        foreach ($control in $fields.Values) {
            if ($control -is [Windows.Controls.PasswordBox]) { $control.Clear() }
        }
    }
}

function New-WinUtilBecamexTaskbarIcon {
    <#
        .SYNOPSIS
            Renders the supplied BECAMEX SVG unchanged for the taskbar overlay.
    #>
    param(
        [double]$Size = 512,
        [switch]$Render
    )

    return New-WinUtilBecamexLogo -Width $Size -Height $Size -FullArtwork -Render:$Render
}

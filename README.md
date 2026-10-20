# Chris Titus Tech's Windows Utility

[![Version](https://img.shields.io/github/v/release/ChrisTitusTech/winutil?color=%230567ff&label=Latest%20Release&style=for-the-badge)](https://github.com/ChrisTitusTech/winutil/releases/latest)
![Downloads](https://img.shields.io/github/downloads/ChrisTitusTech/winutil/winutil.ps1?label=Total%20Downloads&style=for-the-badge)
[![Discord](https://dcbadge.limes.pink/api/server/https://discord.gg/RUbZUZyByQ?theme=default-inverted&style=for-the-badge)](https://discord.gg/RUbZUZyByQ)

Windows utility with separate **Application**, **Update**, **Activation**, **Tweaks**, **Maintenance**, and **AppX Removal** tabs. Update opens Windows Update Settings and Microsoft Store Downloads, and shares a synchronized Windows Update switch with Maintenance. Application has no FOSS legend or badges; Tweaks omits Multiplane Overlay, Performance Plans, and the footer note. Maintenance includes optional E: low-space warnings and a separate WinGet repair panel. AppX Removal excludes Calculator, Notepad, Paint, Photos, Snipping Tool, Camera, Media Player, Sticky Notes, Clock, and To Do; the footer note is removed.

Click **Activation** (Alt+C) to open MAS directly, without a second button. The PowerShell bootstrap runs hidden so only the final MAS menu is shown. It requires Internet access; choose any further action in the MAS menu.

The Windows Update switch applies configuration when its operation completes, without a blanket restart requirement. Changes and service-state checks run in the background to keep the interface responsive. Windows may separately request a restart after installing updates.



---

## Quick Start

> **WinUtil must be run as Administrator** Because it performs system-wide changes.

Download `TamphanITtools.cmd` from [this project's latest release](https://github.com/pttbk9cqt/TamphanITtools/releases/latest), double-click it and approve UAC. It downloads `winutil.ps1` and its SHA-256 checksum from that release, validates them, then runs Windows PowerShell as administrator. No presets, activation, or maintenance tasks run automatically.

For USB/local use, extract `TamphanITtools-portable.zip` and run `TamphanITtools.cmd offline` from that folder. This uses the adjacent `winutil.ps1` without downloading or updating it; installation and other online features still need Internet access. Online failures never silently launch an old local copy. Administrator credentials and organizational security policies still apply.

The online launcher requires a public, non-prerelease release containing `winutil.ps1` and `winutil.ps1.sha256`. GitHub's automatic source-code ZIP alone is not sufficient. The checksum detects mismatched/corrupt downloads; it is not a digital signature or protection against a compromised release account.

Application selection stays in the app list, without a Selected Apps popup. Tweaks offers All and Clear (All selects checkboxes without applying switches); named presets remain available through the command line. AppX selection offers Select All and Clear Selection. Maintenance includes Restart Explorer and returns focus to its tab after completion feedback.

### How to open an admin terminal

- **Start menu:** Right-click Start → *Windows PowerShell (Admin)* or *Terminal (Admin)*
- **Search:** Press the `Windows key`, and type `PowerShell` or `Terminal`, then `Ctrl + Shift + Enter`

---

## Automation / Presets

Apply a predefined configuration without manual selection:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\winutil.ps1 -Preset Standard
```

| Preset | Description |
|--------|-------------|
| `Standard` | Balanced defaults for most users |
| `Minimal` | Minimal changes to suit every user |
| `Advanced` | Deep tweaks for power users |

To view exactly what each preset does, see:
https://github.com/ChrisTitusTech/winutil/blob/main/config/preset.json

---

## Build & Develop

See https://github.com/ChrisTitusTech/winutil/blob/main/.github/CONTRIBUTING.md

To prepare this fork's launcher and USB package locally:

```powershell
.\Build-Portable.ps1
```

This compiles sources and writes four files into ignored `binary/`: `winutil.ps1`, `winutil.ps1.sha256`, `TamphanITtools.cmd`, and `TamphanITtools-portable.zip`. Upload these files as assets of a stable release in this repository. Do not commit generated files. The build command does not publish anything; the existing pre-release workflow does not supply a stable latest release.

---

## Resources

- [Upstream Documentation](https://winutil.christitus.com/)
- [YouTube Tutorial](https://www.youtube.com/watch?v=6UQZ5oQg8XA)
- [ChrisTitus.com Article](https://christitus.com/windows-tool/)
- [Known Issues](https://winutil.christitus.com/knownissues/)
- [Report an Issue](https://github.com/ChrisTitusTech/winutil/issues)

---

## Support

- Leave a ⭐ to show support!
- Faster Dotnet Implementation for sale here: https://www.cttstore.com/windows-toolbox

## Sponsors

These are the sponsors that help keep this project alive with monthly contributions.

<!-- sponsors --><a href="https://github.com/dwelfusius"><img src="https:&#x2F;&#x2F;github.com&#x2F;dwelfusius.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/mews-se"><img src="https:&#x2F;&#x2F;github.com&#x2F;mews-se.png" width="60px" alt="User avatar: Martin" /></a><a href="https://github.com/jdiegmueller"><img src="https:&#x2F;&#x2F;github.com&#x2F;jdiegmueller.png" width="60px" alt="User avatar: Jason A. Diegmueller" /></a><a href="https://github.com/robertsandrock"><img src="https:&#x2F;&#x2F;github.com&#x2F;robertsandrock.png" width="60px" alt="User avatar: RMS" /></a><a href="https://github.com/paulsheets"><img src="https:&#x2F;&#x2F;github.com&#x2F;paulsheets.png" width="60px" alt="User avatar: Paul" /></a><a href="https://github.com/djones369"><img src="https:&#x2F;&#x2F;github.com&#x2F;djones369.png" width="60px" alt="User avatar: Dave J  (WhamGeek)" /></a><a href="https://github.com/anthonymendez"><img src="https:&#x2F;&#x2F;github.com&#x2F;anthonymendez.png" width="60px" alt="User avatar: Anthony Mendez" /></a><a href="https://github.com/FatBastard0"><img src="https:&#x2F;&#x2F;github.com&#x2F;FatBastard0.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/DursleyGuy"><img src="https:&#x2F;&#x2F;github.com&#x2F;DursleyGuy.png" width="60px" alt="User avatar: DursleyGuy" /></a><a href="https://github.com/DwayneTheRockLobster1"><img src="https:&#x2F;&#x2F;github.com&#x2F;DwayneTheRockLobster1.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/KieraKujisawa"><img src="https:&#x2F;&#x2F;github.com&#x2F;KieraKujisawa.png" width="60px" alt="User avatar: Kiera Meredith" /></a><a href="https://github.com/seanh1995"><img src="https:&#x2F;&#x2F;github.com&#x2F;seanh1995.png" width="60px" alt="User avatar: Sean (ANGRYxScotsman)" /></a><a href="https://github.com/Abs313a"><img src="https:&#x2F;&#x2F;github.com&#x2F;Abs313a.png" width="60px" alt="User avatar: Abs" /></a><a href="https://github.com/kydoa"><img src="https:&#x2F;&#x2F;github.com&#x2F;kydoa.png" width="60px" alt="User avatar: Daniel Scheuermann" /></a><a href="https://github.com/hafiz-muhammad"><img src="https:&#x2F;&#x2F;github.com&#x2F;hafiz-muhammad.png" width="60px" alt="User avatar: Abdul Hafiz Muhammad" /></a><!-- sponsors -->

---

## Contributors

[![Contributors](https://contrib.rocks/image?repo=ChrisTitusTech/winutil)](https://github.com/ChrisTitusTech/winutil/graphs/contributors)

Thanks to everyone who has contributed time and effort to this project. Keep rocking 🍻

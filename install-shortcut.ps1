<#
.SYNOPSIS
Creates or refreshes the Windows shortcuts that launch this checkout.

.DESCRIPTION
Target, arguments, working directory and icon are resolved from the folder holding this script, so the
shortcut follows the checkout instead of a path recorded when it was first created. Run the script again
after the checkout moves or is copied somewhere else.

.PARAMETER Destination
Folders that receive "DeepSeek Harness.lnk". Defaults to the checkout root.

.PARAMETER Desktop
Also install the shortcut on the desktop of the current user.

.PARAMETER StartMenu
Also install the shortcut in the Start Menu programs folder of the current user.

.EXAMPLE
.\install-shortcut.ps1 -Desktop

Creates the shortcut in the checkout root and on the desktop.
#>
[CmdletBinding()]
param(
    [string[]] $Destination = @(),
    [switch] $Desktop,
    [switch] $StartMenu
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$launcher = Join-Path $root 'start-web-silent.vbs'
$icon = Join-Path $root 'dsh-harness.ico'
$interpreter = Join-Path $env:SystemRoot 'System32\wscript.exe'
foreach ($required in $launcher, $icon, $interpreter) {
    if (-not (Test-Path -LiteralPath $required)) { throw "missing required file: $required" }
}

$folders = [System.Collections.Generic.List[string]]::new()
foreach ($folder in $Destination) { $folders.Add($folder) }
if ($folders.Count -eq 0) { $folders.Add($root) }
if ($Desktop) { $folders.Add([Environment]::GetFolderPath('Desktop')) }
if ($StartMenu) { $folders.Add([Environment]::GetFolderPath('Programs')) }

$shell = New-Object -ComObject WScript.Shell
foreach ($folder in $folders) {
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $linkPath = Join-Path $folder 'DeepSeek Harness.lnk'
    $link = $shell.CreateShortcut($linkPath)
    $link.TargetPath = $interpreter
    $link.Arguments = '"' + $launcher + '"'
    $link.WorkingDirectory = $root
    $link.IconLocation = "$icon,0"
    $link.Description = 'DeepSeek Harness'
    $link.WindowStyle = 1
    $link.Save()
    Write-Host "shortcut: $linkPath"
}

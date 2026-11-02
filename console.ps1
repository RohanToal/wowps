<#
.SYNOPSIS
Open the world server console to type GM commands.

.DESCRIPTION
Examples of commands to type:
  account create NAME PASSWORD
  account set gmlevel NAME 3 -1
Press Ctrl+C to leave. The server keeps running.

.EXAMPLE
.\console.ps1
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'scripts/lib.ps1')

Invoke-Main {
    Assert-Docker
    if (-not (Test-ContainerRunning 'ac-worldserver')) { Fail 'The server is not running. Start it with .\start.ps1' }

    Write-Host 'Connected to the server console. Type a command and press Enter, e.g.'
    Write-Host '    account create myname mypassword'
    Write-Host '    account set gmlevel myname 3 -1'
    Write-Host 'Press Enter once to see the AC> prompt. Press Ctrl+C to leave (the server keeps running).'
    Write-Host ''
    # Ctrl+C is turned into "detach" so it can't shut the server down by accident.
    # Called directly (not through a pipe) so the console stays interactive.
    $ErrorActionPreference = 'Continue'
    & docker attach --detach-keys=ctrl-c ac-worldserver
    Write-Host ''
    Write-Ok 'Left the console. The server is still running.'
}

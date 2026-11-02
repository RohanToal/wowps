<#
.SYNOPSIS
Stop the server.

.DESCRIPTION
The world server saves all characters first, which can take a minute with
many bots. Accounts, characters and settings are kept.

.EXAMPLE
.\stop.ps1
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'scripts/lib.ps1')

Invoke-Main {
    Assert-Docker
    Assert-EnvFile

    Write-Info 'Stopping the server (saving characters first)...'
    Invoke-Compose -Arguments @('down', '--remove-orphans')
    Write-Ok 'Server stopped.'
}

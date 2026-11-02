<#
.SYNOPSIS
Start the server and wait until the world is ready.

.DESCRIPTION
Starts the database, auth server and world server. The first start takes
longer: it creates the databases and, with bots enabled, creates the bot
accounts and characters.

.EXAMPLE
.\start.ps1
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'scripts/lib.ps1')

Invoke-Main {
    Assert-Docker
    Assert-EnvFile
    Assert-Images
    Initialize-Dirs

    if (-not (Test-DbVolume)) {
        Write-Info 'First start: creating the databases. This takes a few minutes...'
    }

    Write-Info 'Starting the server...'
    $code = Invoke-NativeCode -File 'docker' -Arguments @('compose', 'up', '-d', '--no-build', '--remove-orphans')
    if ($code -ne 0) {
        Show-FailedOneshots
        Fail "The server could not start. See the messages above, and 'Troubleshooting' in the README."
    }

    Write-Info 'Waiting for the world server to finish loading (with many bots this can take several minutes)...'
    if (-not (Wait-Worldserver)) {
        Fail 'The world server did not start. Full log: docker logs ac-worldserver   (or logs\Server.log)'
    }

    Write-ConnectInfo
}

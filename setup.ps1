<#
.SYNOPSIS
First-time setup (safe to run again).

.DESCRIPTION
1. checks Docker and git
2. creates .env with a random database password
3. downloads the pinned AzerothCore + mod-playerbots source into .\source
4. downloads the server map data into a Docker volume
5. builds the server images (takes a while the first time)

.EXAMPLE
.\setup.ps1
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'scripts/lib.ps1')

Invoke-Main {
    Write-Host '=============================================================='
    Write-Host ' WoW 3.3.5a personal server: AzerothCore + mod-playerbots'
    Write-Host '=============================================================='

    Write-Info 'Checking prerequisites...'
    Assert-Git
    Assert-Docker
    Write-Ok 'git and Docker found'

    Write-Info 'Preparing settings...'
    Initialize-EnvFile
    Initialize-Dirs

    Write-Info 'Getting the pinned server source code...'
    Sync-Sources

    # Build the small download image first so a network problem shows up
    # before the long compile.
    New-WowpsDockerfile -Jobs (Get-BuildJobs)
    Write-Info 'Preparing the map data downloader...'
    Invoke-Compose -Arguments @('build', 'ac-client-data-init')
    Invoke-DownloadClientData

    if (-not (Invoke-BuildImages)) {
        Fail "The build failed. If the log says 'Killed' or 'signal 9', set BUILD_JOBS=2 in .env (or give Docker Desktop more memory) and run .\setup.ps1 again."
    }

    Write-Host ''
    Write-Ok 'Setup finished.'
    Write-Host ''
    Write-Host 'Next steps:'
    Write-Host '  1. (optional) Edit .env: realm name, bot counts, REALM_ADDRESS for LAN play.'
    $ip = Get-LanIp
    if ($ip) { Write-Host "     This computer's LAN IP looks like: $ip" }
    Write-Host '  2. Start the server:        .\start.ps1'
    Write-Host "  3. Create your account:     see 'Create your game account' in README.md"
}

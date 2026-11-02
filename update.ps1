<#
.SYNOPSIS
Update the server to the commits pinned in versions.env.

.DESCRIPTION
  .\update.ps1           build the versions in versions.env (do a `git pull`
                         of this repo first to get newer pins)
  .\update.ps1 -Latest   move the pins to the newest upstream commits first
  .\update.ps1 -Rebuild  rebuild even if nothing changed

Order of work: download source -> build new images (server keeps running) ->
back up -> stop -> update map data if needed -> start (database updates are
applied automatically on start). If the build fails, the previous source and
pins are put back and your server is untouched.

.EXAMPLE
.\update.ps1

.EXAMPLE
.\update.ps1 -Latest
#>
[CmdletBinding()]
param(
    [switch]$Latest,
    [switch]$Rebuild
)

. (Join-Path $PSScriptRoot 'scripts/lib.ps1')

Invoke-Main {
    Assert-Git
    Assert-Docker
    Assert-EnvFile
    if (-not (Test-Path -LiteralPath (Join-Path $script:AcDir '.git'))) { Fail 'No source checkout found. Run .\setup.ps1 first.' }
    Initialize-Dirs

    $oldVersions = [System.IO.File]::ReadAllLines($script:VersionsFile)
    $oldAc = Get-SourceCommit $script:AcDir
    $oldPb = Get-SourceCommit $script:PbDir

    if ($Latest) {
        $v = Read-Versions
        Write-Info 'Looking up the newest upstream commits...'
        $newAc = ((Get-NativeOutput -File 'git' -Arguments @('ls-remote', $v['AC_REPO'], "refs/heads/$($v['AC_BRANCH'])")) -split '\s+')[0]
        $newPb = ((Get-NativeOutput -File 'git' -Arguments @('ls-remote', $v['PLAYERBOTS_REPO'], "refs/heads/$($v['PLAYERBOTS_BRANCH'])")) -split '\s+')[0]
        if (-not $newAc -or -not $newPb) { Fail 'Could not look up upstream branches. Check your internet connection.' }
        Set-EnvValue -Key 'AC_COMMIT' -Value $newAc -File $script:VersionsFile
        Set-EnvValue -Key 'PLAYERBOTS_COMMIT' -Value $newPb -File $script:VersionsFile
        Write-Host "   AzerothCore:    $(Get-Short $v['AC_COMMIT']) -> $(Get-Short $newAc)"
        Write-Host "   mod-playerbots: $(Get-Short $v['PLAYERBOTS_COMMIT']) -> $(Get-Short $newPb)"
        Write-Warn 'These newer commits have not been tested together by this repo.'
    }

    $v = Read-Versions
    if ($oldAc -eq $v['AC_COMMIT'] -and $oldPb -eq $v['PLAYERBOTS_COMMIT'] -and (Test-ImagesExist) -and -not $Rebuild) {
        Write-Ok "Already up to date (AzerothCore $(Get-Short $v['AC_COMMIT']), mod-playerbots $(Get-Short $v['PLAYERBOTS_COMMIT']))."
        return
    }

    $rollback = {
        Write-Warn 'Putting the previous source and versions.env back...'
        Write-LfFile -Path $script:VersionsFile -Lines $oldVersions
        $prev = Read-Versions
        if ($oldAc) { Sync-Repo -Dir $script:AcDir -Url $prev['AC_REPO'] -Commit $oldAc }
        if ($oldPb) { Sync-Repo -Dir $script:PbDir -Url $prev['PLAYERBOTS_REPO'] -Commit $oldPb }
        New-WowpsDockerfile -Jobs (Get-BuildJobs)
    }

    Write-Info 'Getting the new source code...'
    try {
        Sync-Sources
    }
    catch {
        Write-Warn $_.Exception.Message
        & $rollback
        Fail 'Download failed. Nothing was changed.'
    }

    if (-not (Invoke-BuildImages)) {
        & $rollback
        Fail ("The build failed, so the update was cancelled. Your server still runs the previous version.`n" +
            "       If you used -Latest, upstream may be broken right now: try again in a few days, or`n" +
            "       stay on the versions this repo pins. If the log says 'Killed', set BUILD_JOBS=2 in .env.")
    }
    Write-Ok 'New images built.'

    $wasRunning = Test-ContainerRunning 'ac-worldserver'

    if (Test-DbVolume) {
        Write-Info 'Backing up before applying the update...'
        $dbWasRunning = Test-ContainerRunning 'ac-database'
        Invoke-DbTools -Arguments @('backup', 'before-update')
        if (-not $dbWasRunning) { [void](Test-Native -File 'docker' -Arguments @('compose', 'down')) }
    }

    if ($wasRunning) {
        Write-Info 'Stopping the server...'
        Invoke-Compose -Arguments @('down', '--remove-orphans')
    }

    Invoke-DownloadClientData

    $v = Read-Versions
    Write-Ok "Update installed: AzerothCore $(Get-Short $v['AC_COMMIT']), mod-playerbots $(Get-Short $v['PLAYERBOTS_COMMIT'])."
    if ($wasRunning) {
        & (Join-Path $script:Root 'start.ps1')
        if ($LASTEXITCODE -ne 0) { Fail 'The server did not start after the update. See Troubleshooting in the README.' }
    }
    else {
        Write-Host 'Start the server with .\start.ps1 (database updates are applied on start).'
    }
}

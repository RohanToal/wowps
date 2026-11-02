<#
.SYNOPSIS
Back up all databases plus config\ and .env into .\backups.

.DESCRIPTION
Saves accounts, characters, bots and the world database into
.\backups\<date>_<time>[_label]. Works whether the server is running or not.
Old backups beyond BACKUP_KEEP (in .env) are deleted.

.EXAMPLE
.\backup.ps1

.EXAMPLE
.\backup.ps1 before-raid
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Label = ''
)

. (Join-Path $PSScriptRoot 'scripts/lib.ps1')

Invoke-Main {
    Assert-Docker
    Assert-EnvFile
    Initialize-Dirs

    if (-not (Test-DbVolume)) { Fail 'There is no database yet. Start the server once first.' }

    $dbWasRunning = Test-ContainerRunning 'ac-database'

    Write-Info 'Backing up...'
    $toolArgs = @('backup')
    if ($Label) { $toolArgs += $Label }
    Invoke-DbTools -Arguments $toolArgs

    # If the database was only started for the backup, stop it again.
    if (-not $dbWasRunning) { [void](Test-Native -File 'docker' -Arguments @('compose', 'down')) }
    Write-Ok 'Backup complete.'
}

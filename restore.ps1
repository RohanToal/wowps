<#
.SYNOPSIS
Restore the databases from a backup in .\backups.

.DESCRIPTION
Everything since that backup (new characters, progress...) is lost. Files in
config\ are NOT changed; the backup's copy is in backups\<name>\config.tar.gz
if you need it. Run without a name to list the backups.

.EXAMPLE
.\restore.ps1

.EXAMPLE
.\restore.ps1 2026-11-02_20-15-00_before-update
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Name = '',
    [switch]$Yes
)

. (Join-Path $PSScriptRoot 'scripts/lib.ps1')

Invoke-Main {
    Assert-Docker
    Assert-EnvFile

    $backupDir = Join-Path $script:Root 'backups'
    $Name = $Name.TrimEnd('\', '/') -replace '^backups[\\/]', ''

    if (-not $Name) {
        Write-Host 'Available backups (newest last):'
        $dirs = @()
        if (Test-Path -LiteralPath $backupDir) {
            $dirs = @(Get-ChildItem -LiteralPath $backupDir -Directory | Where-Object { $_.Name -notlike '*.partial' } | Sort-Object Name)
        }
        if ($dirs.Count -eq 0) { Write-Host '  (none)' } else { $dirs | ForEach-Object { Write-Host $_.Name } }
        Write-Host ''
        Write-Host 'Usage: .\restore.ps1 <backup-name>'
        Fail 'No backup name given.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $backupDir $Name))) {
        Fail "Backup 'backups\$Name' not found. Run .\restore.ps1 to list backups."
    }

    if (-not $Yes) {
        Write-Warn "This replaces ALL accounts, characters and bots with the backup '$Name'."
        $answer = Read-Host 'Type "yes" to continue'
        if ($answer -ne 'yes') { Fail 'Cancelled.' }
    }

    $wasRunning = Test-ContainerRunning 'ac-worldserver'

    Write-Info 'Stopping the game servers...'
    [void](Test-Native -File 'docker' -Arguments @('compose', 'stop', 'ac-worldserver', 'ac-authserver'))

    Write-Info "Restoring backups\$Name ..."
    Invoke-DbTools -Arguments @('restore', $Name)
    Write-Ok 'Database restored.'

    if ($wasRunning) {
        & (Join-Path $script:Root 'start.ps1')
        if ($LASTEXITCODE -ne 0) { Fail 'The server did not start after the restore.' }
    }
    else {
        [void](Test-Native -File 'docker' -Arguments @('compose', 'down'))
        Write-Host 'Start the server with .\start.ps1'
    }
}
